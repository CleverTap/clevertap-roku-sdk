' Public SDK node. The app creates one of these, keeps it on m.global, and drives it with
' callfunc: init() once, then recordEvent / recordChargedEvent as things happen.
'
' This node holds all the SDK state (config, device id, session, queue) and owns two child
' nodes: a Timer that debounces uploads, and a CleverTapTask that does the actual network
' I/O off the render thread. Recorded items land in the queue and are flushed a moment
' later (or immediately once a full batch has built up).

' Serves double duty. The SceneGraph runtime calls init() with no args when the node is
' created; the app later calls callfunc("init", config) to configure the SDK. The optional
' parameter lets one function handle both: no config means "just created, stay inert until
' configured". m.started guards every public call so an unconfigured SDK does nothing.
'
' config carries accountId/token and optionally region or proxyDomain; any missing value
' falls back to the manifest.
function init(config = invalid as dynamic) as void
    ' On creation the SceneGraph runtime calls init() with no args. Don't use an explicit
    ' `return` for that path: some SceneGraph runtimes invoke a component's init in a way that
    ' lets an explicit return escape node creation and error out. So we branch here instead of
    ' early-returning, and only configure when a config was actually passed.
    if config = invalid then
        m.started = false
    else
        appInfo = CreateObject("roAppInfo")
        m.config = CleverTapResolveCredentials(config, appInfo)
        ' Set the level before anything else logs, so an early failure obeys it.
        CleverTapLogSetLevel(m.config.logLevel)
        if m.config.accountId = "" or m.config.token = "" then
            CleverTapLogError("missing account id or token, SDK inactive")
            return
        end if

        ' Everything durable is namespaced per account so two accounts never collide.
        m.storage = CleverTapStorage("clevertap_" + m.config.accountId)
        m.deviceId = CleverTapDeviceGetId(m.storage)
        deviceInfo = CreateObject("roDeviceInfo")
        ' Read before the app fields are built. "useIP" is one of those fields.
        m.reportNetworkInfo = (m.storage.read(CleverTapConstants().NETWORK_INFO_KEY) = "1")
        m.appFields = CleverTapDeviceAppFields(deviceInfo, appInfo, m.reportNetworkInfo)
        ' Kept so the app fields can be built again if the app changes the setting later.
        m.appInfo = appInfo
        ' What the viewer chose last time this device id was used. A new device id has made
        ' no choice, so it starts opted in.
        m.privacy = CleverTapPrivacyDecode(m.storage.read(CleverTapPrivacyStorageKey(m.deviceId)))
        ' The country and the time zone are profile attributes, not app fields, so they are
        ' read once here and sent by ctPushDeviceProfile below.
        m.countryCode = CleverTapCountryCode(deviceInfo)
        m.timeZone = CleverTapDeviceTimeZone(deviceInfo)
        m.session = CleverTapSession(m.storage)
        m.meta = CleverTapMeta(m.storage)
        m.queue = CleverTapQueue(m.storage)
        m.queue.load()
        CleverTapLogDebug("queued items restored from storage: " + m.queue.count().ToStr())
        ctWarnIfRegistryLow()

        m.redirectKey = "redirectDomain"
        m.identityCacheKey = "identityCache"
        m.identifiedKey = "identified"
        m.cachedRedirect = m.storage.read(m.redirectKey)
        m.arpKey = "arp"
        ' The block the server sent back last time, repeated in the header of every request.
        m.arp = ctLoadArp()
        ' The events the dashboard has switched off. Held for this run only; the server sends
        ' the list again with every reply.
        m.discardedEvents = []
        m.failureCount = 0
        m.muted = false
        m.inFlight = false
        ' Names the items in the request that is on its way. Used by the log only.
        m.inFlightDescription = ""
        ' The highest sequence number the request on its way took from each queue. Set by
        ' ctFlush and read when the server replies. 0 means it took nothing from that queue.
        m.inFlightProfileSeq = 0
        m.inFlightEventSeq = 0
        ' Tracks whether this run has recorded its App Launched event yet. Starts false on
        ' every node creation (so once per channel launch) and is re-armed whenever a new
        ' session begins - see ctEnsureSession.
        m.appLaunchRecorded = false

        ' Child that runs roUrlTransfer on its own thread; we watch its response field.
        m.task = m.top.CreateChild("CleverTapTask")
        m.task.observeField("response", "ctOnUploadResult")

        ' Debounce timer: recording an event (re)starts it, so a burst of events uploads once.
        m.timer = m.top.CreateChild("Timer")
        m.timer.repeat = false
        m.timer.observeField("fire", "ctOnFlushTimer")

        m.started = true
        CleverTapLogInfo("initialized, account " + m.config.accountId + ", sdk " + CleverTapConstants().SDK_VERSION)
        CleverTapLogDebug("device id " + m.deviceId)
        ' Only worth a line when the viewer opted out. The usual state needs no announcing.
        if m.privacy.optedOut then CleverTapLogInfo("this viewer is " + CleverTapPrivacyDescribe(m.privacy))
        ' Fire App Launched for this launch (the mobile SDKs do the same on cold start), then
        ' send it alongside anything left over from a previous run (e.g. events queued offline).
        ctEnsureSession(ctNow())
        ctPushDeviceProfile()
        ctScheduleFlush()
    end if
end function

' Records a custom event. args is [name, props]; props is optional.
function recordEvent(args as object) as void
    if not m.started then return
    if args = invalid or args.Count() = 0 then return

    name = args[0]
    props = invalid
    if args.Count() > 1 then props = args[1]

    check = CleverTapValidator().validateEventName(name)
    if not check.valid then
        CleverTapLogError("event rejected, " + check.message)
        return
    end if

    ' The dashboard can switch an event off. The server then throws it away on arrival, so
    ' there is no reason to queue it or to spend a request on it.
    if CleverTapIsDiscardedEvent(check.value, m.discardedEvents) then
        CleverTapLogDebug("event '" + check.value + "' is switched off in the dashboard, so it was not recorded")
        return
    end if

    if not ctPrivacyAllows("event", check.value) then return

    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueEvent(CleverTapBuildEvent(check.value, props, m.session.meta(), now))
    CleverTapLogInfo("event recorded: " + check.value)
    ctMaybeFlush()
end function

' Records a purchase. args is [details, items]; details holds Amount etc., items is the line
' items array. Both ride in a reserved "Charged" event.
function recordChargedEvent(args as object) as void
    if not m.started then return
    if args = invalid or args.Count() = 0 then return

    if not ctPrivacyAllows("event", CleverTapConstants().CHARGED_EVENT_NAME) then return

    details = args[0]
    items = invalid
    if args.Count() > 1 then items = args[1]

    itemCount = 0
    if items <> invalid then itemCount = items.Count()

    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueEvent(CleverTapBuildChargedEvent(details, items, m.session.meta(), now))
    CleverTapLogInfo("charged event recorded, line items: " + itemCount.ToStr())
    ctMaybeFlush()
end function

' Sets attributes on the current user. args is [profileFields], a map of attribute
' name -> value. Goes into the profile queue so it ships ahead of events on the next flush.
function profilePush(args as object) as void
    if not m.started then return
    if args = invalid or args.Count() = 0 then return

    fields = args[0]
    if fields = invalid then return
    if not ctPrivacyAllows("profile", "") then return

    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueProfile(CleverTapBuildProfile(fields, m.session.meta(), now, ctDeviceCountryCode()))
    CleverTapLogInfo("profile recorded, fields: " + fields.Count().ToStr())
    ctMaybeFlush()
end function

' Identifies a user and sets their attributes. args is [profileFields], where the map may
' carry an identity field (Identity, Email, or Phone). Depending on whether that identity is
' new, returning, or already active, this may switch to a different device id first.
function onUserLogin(args as object) as void
    if not m.started then return
    if args = invalid or args.Count() = 0 then return

    input = args[0]
    if input = invalid then return

    cache = ctLoadIdentityCache()
    identified = (m.storage.read(m.identifiedKey) = "1")
    ' Candidate id used only if this turns out to be a brand-new user.
    newId = CreateObject("roDeviceInfo").GetRandomUUID()

    decision = CleverTapResolveLogin(input, m.deviceId, identified, cache, newId)
    CleverTapLogInfo("login: " + ctLoginOutcomeText(decision))

    if decision.action = "switch" then
        ' Moving to a different user: drop the previous user's unsent items so they can't be
        ' attributed to this one, and start a fresh session under the new id.
        CleverTapLogDebug("unsent items dropped for the previous user: " + m.queue.count().ToStr())
        m.queue.clear()
        m.session.reset()
        ' What the server sent back was about the previous user, so it is not repeated under
        ' the new id.
        ctResetArp()
        m.deviceId = decision.deviceId
        CleverTapDeviceSetId(m.storage, decision.deviceId)
        CleverTapLogInfo("device id is now " + decision.deviceId)
        ' The choice belongs to the viewer, not to the device. This is a different viewer, so
        ' their own choice is loaded. A viewer who has never chosen starts opted in. A viewer
        ' who opted out before is still opted out.
        m.privacy = CleverTapPrivacyDecode(m.storage.read(CleverTapPrivacyStorageKey(m.deviceId)))
        if m.privacy.optedOut then CleverTapLogInfo("this viewer is " + CleverTapPrivacyDescribe(m.privacy))
    end if

    ' Remember the identity -> id mapping and that the device is now identified.
    '
    ' This happens even for a viewer who opted out. The mapping never leaves the device. It
    ' is what lets this viewer keep the same device id the next time they sign in. Skipping
    ' it would build a new id on every sign-in, and the opt-out kept against the old id
    ' would stop applying.
    if decision.cacheKey <> invalid then
        cache[decision.cacheKey] = decision.deviceId
        ctSaveIdentityCache(cache)
        m.storage.write(m.identifiedKey, "1")
    end if

    if not ctPrivacyAllows("profile", "") then return

    ' Push the supplied attributes under the (possibly new) id. On a switch the session was
    ' just reset, so ctEnsureSession starts a fresh one and fires App Launched into the now
    ' empty queue ahead of this profile - matching the mobile clear -> App Launched -> profile
    ' order.
    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueProfile(CleverTapBuildProfile(input, m.session.meta(), now, ctDeviceCountryCode()))
    CleverTapLogInfo("profile recorded, fields: " + input.Count().ToStr())
    ctMaybeFlush()
end function

' Describes what a login did, for the log. The resolver names its outcomes for the code that
' reads them. Those names are not written to the log, because the log is read by people
' integrating the SDK.
function ctLoginOutcomeText(decision as object) as string
    if decision.action = "profileOnly" then
        return "no identifying field was sent. The attributes go on the current user."
    end if
    if decision.action = "claim" then
        return "no user was identified on this device before. The current device id now belongs to this user."
    end if
    if decision.action = "same" then
        return "this is already the current user. Only the attributes are updated."
    end if
    if decision.isNew then
        return "this user is seen for the first time. A new device id is created."
    end if
    return "this user is known on this device. Their earlier device id is restored."
end function

' --- profile commands ---
'
' profilePush replaces the value of a key. The calls below change part of a value instead, so
' the app does not have to read the old value first. Every one of them takes args in the same
' shape: [key, value]. The key comes first, matching the Android SDK.
'
' The SDK keeps no copy of the profile. It sends the command and the server applies it, so
' nothing here reads the current value.

' Removes a property from the profile. args is [key].
function profileRemoveValueForKey(args as object) as void
    if not m.started then return
    if args = invalid or args.Count() = 0 then return
    ctEnqueueProfileCommand(args[0], CleverTapConstants().PROFILE_COMMAND_DELETE, true)
end function

' Replaces the whole list of a multi-value property. args is [key, values], where values is
' an array. Every value is sent as text.
function profileSetMultiValues(args as object) as void
    if not m.started then return
    ctProfileMultiValue(args, CleverTapConstants().PROFILE_COMMAND_SET)
end function

' Puts one value into a multi-value property. args is [key, value].
function profileAddMultiValue(args as object) as void
    if not m.started then return
    ctProfileMultiValue(ctSingleValueArgs(args), CleverTapConstants().PROFILE_COMMAND_ADD)
end function

' Puts several values into a multi-value property. args is [key, values].
function profileAddMultiValues(args as object) as void
    if not m.started then return
    ctProfileMultiValue(args, CleverTapConstants().PROFILE_COMMAND_ADD)
end function

' Takes one value out of a multi-value property. args is [key, value].
function profileRemoveMultiValue(args as object) as void
    if not m.started then return
    ctProfileMultiValue(ctSingleValueArgs(args), CleverTapConstants().PROFILE_COMMAND_REMOVE)
end function

' Takes several values out of a multi-value property. args is [key, values].
function profileRemoveMultiValues(args as object) as void
    if not m.started then return
    ctProfileMultiValue(args, CleverTapConstants().PROFILE_COMMAND_REMOVE)
end function

' Raises a number property by an amount. args is [key, amount]. The amount must be above
' zero.
function profileIncrementValueBy(args as object) as void
    if not m.started then return
    ctProfileAmount(args, CleverTapConstants().PROFILE_COMMAND_INCREMENT)
end function

' Lowers a number property by an amount. args is [key, amount]. The amount must be above
' zero: pass the size of the drop, not a negative number.
function profileDecrementValueBy(args as object) as void
    if not m.started then return
    ctProfileAmount(args, CleverTapConstants().PROFILE_COMMAND_DECREMENT)
end function

' Turns the args of a one-value call into the args of the matching list call, so both follow
' one path. [key, value] becomes [key, [value]].
function ctSingleValueArgs(args as object) as object
    if args = invalid or args.Count() < 2 then return args
    return [args[0], [args[1]]]
end function

' Shared body of the $set, $add and $remove calls. args is [key, values].
sub ctProfileMultiValue(args as object, command as string)
    if args = invalid or args.Count() < 2 then return

    check = CleverTapNormaliseMultiValues(args[1])
    if not check.valid then
        CleverTapLogError("profile change rejected, " + check.message)
        return
    end if
    ctEnqueueProfileCommand(args[0], command, check.value)
end sub

' Shared body of the $incr and $decr calls. args is [key, amount].
sub ctProfileAmount(args as object, command as string)
    if args = invalid or args.Count() < 2 then return

    check = CleverTapValidateCommandAmount(args[1])
    if not check.valid then
        CleverTapLogError("profile change rejected, " + check.message)
        return
    end if
    ctEnqueueProfileCommand(args[0], command, check.value)
end sub

' Checks the key and queues one command. Commands go into the profile queue, like
' profilePush, so they ship ahead of events on the next flush.
sub ctEnqueueProfileCommand(key as dynamic, command as string, value as dynamic)
    check = CleverTapValidateCommandKey(key)
    if not check.valid then
        CleverTapLogError("profile change rejected, " + check.message)
        return
    end if

    if not ctPrivacyAllows("profile", "") then return

    now = ctNow()
    ctEnsureSession(now)
    item = CleverTapBuildProfileCommand(check.value, command, value, m.session.meta(), now)
    m.queue.enqueueProfile(item)
    CleverTapLogInfo("profile changed: " + CleverTapDescribeProfileCommand(command, check.value, value))
    ' The line above says what changed. This one shows the exact change that goes on the wire,
    ' which is the one that answers "did it send what I passed".
    CleverTapLogDebug("profile change is " + FormatJson(item.profile))
    ctMaybeFlush()
end sub

' --- privacy ---

' Stops or resumes reporting for the viewer on this device.
'
' args is [optedOut] or [optedOut, allowSystemEvents].
'
' setOptOut([true]) stops everything. Nothing the app records is sent, and the SDK sends
' nothing of its own either.
'
' setOptOut([true, true]) stops only what the app records. The SDK still reports that a
' channel opened, so sessions on the server still close properly. Use this when the viewer
' asked not to be tracked but the app still needs usage figures that name nobody.
'
' setOptOut([false]) resumes everything.
'
' The choice is kept on the device against the current device id. It survives the channel
' closing. An app does not have to call this on every launch. Calling it on every launch
' with the viewer's stored answer is still good practice, because the app is the place that
' answer really lives.
function setOptOut(args as object) as void
    if not m.started then return
    if args = invalid or args.Count() = 0 then return
    if GetInterface(args[0], "ifBoolean") = invalid then
        CleverTapLogError("setOptOut needs true or false")
        return
    end if

    optedOut = args[0]
    ' One argument means a full opt-out, matching the mobile SDKs.
    allowSystemEvents = not optedOut
    if args.Count() > 1 and GetInterface(args[1], "ifBoolean") <> invalid then
        allowSystemEvents = args[1]
    end if

    state = CleverTapPrivacyResolve(optedOut, allowSystemEvents)

    ' The server is told by a profile change, and that change has to get past the same gate
    ' it is setting. So the order differs between the two directions.
    '
    ' Opting out: send the change first, then close the gate. Closing it first would drop
    ' the very message that reports the opt-out.
    '
    ' Opting in: open the gate first, then send the change.
    if state.optedOut then
        ctEnqueuePrivacyProfile(state)
        m.privacy = state
    else
        m.privacy = state
        ctEnqueuePrivacyProfile(state)
    end if

    m.storage.write(CleverTapPrivacyStorageKey(m.deviceId), CleverTapPrivacyEncode(state))
    CleverTapLogInfo("this viewer is " + CleverTapPrivacyDescribe(state))
end function

' Queues the profile change that tells the server about the choice. Written without the
' privacy gate on purpose: setOptOut has already decided this one may go.
sub ctEnqueuePrivacyProfile(state as object)
    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueProfile(CleverTapBuildProfile(CleverTapPrivacyProfileFields(state), m.session.meta(), now, ctDeviceCountryCode()))
    ctMaybeFlush()
end sub

' Turns reporting of network details on or off. args is [enabled].
'
' This is off unless the app turns it on. While it is off the SDK reports nothing about the
' connection, and it tells the server not to work out where the viewer is from the address
' the request came from.
'
' Turning it on adds whether the device is on WiFi, and lets the server read the location
' from the request address. A Roku device has no mobile radio, so there is no mobile network
' to report.
'
' The setting is kept on the device and applies to every viewer on it.
function enableDeviceNetworkInfoReporting(args as object) as void
    if not m.started then return
    if args = invalid or args.Count() = 0 then return
    if GetInterface(args[0], "ifBoolean") = invalid then
        CleverTapLogError("enableDeviceNetworkInfoReporting needs true or false")
        return
    end if

    m.reportNetworkInfo = args[0]
    m.storage.write(CleverTapConstants().NETWORK_INFO_KEY, CleverTapPrivacyFlagChar(m.reportNetworkInfo))

    ' The device fields were built once at init. They carry the setting, so they are built
    ' again here. Without this the change would never reach the server.
    m.appFields = CleverTapDeviceAppFields(CreateObject("roDeviceInfo"), m.appInfo, m.reportNetworkInfo)

    if m.reportNetworkInfo then
        CleverTapLogInfo("network details are now reported")
    else
        CleverTapLogInfo("network details are no longer reported")
    end if
end function

' Checks one item against the viewer's choice. Logs the reason when it says no, because an
' item that quietly never arrives is hard to explain.
function ctPrivacyAllows(kind as string, name as string) as boolean
    if CleverTapPrivacyAllows(kind, name, m.privacy) then return true

    what = "profile change"
    if kind = "event" then what = "event '" + name + "'"
    CleverTapLogDebug(what + " was not recorded, because this viewer is " + CleverTapPrivacyDescribe(m.privacy))
    return false
end function

' Returns the current CleverTap device id (GUID), or "" if the SDK isn't configured yet. This
' is the same id CleverTap shows on the profile, so it's handy for matching a run to the
' dashboard. args is unused.
function getCleverTapID(args = invalid as dynamic) as string
    if not m.started then return ""
    return m.deviceId
end function

' Advances the session for an event at "now" and records App Launched when appropriate:
' the first time this run touches a session (once per channel launch) and again whenever a
' new session begins - i.e. after an inactivity timeout or a user switch. Call this before
' enqueueing the event that triggered it, so App Launched leads the batch.
sub ctEnsureSession(now as integer)
    startedNew = m.session.ensure(now)
    if startedNew then CleverTapLogInfo("new session " + m.session.meta().s.ToStr())
    if (not m.appLaunchRecorded) or startedNew then ctRecordAppLaunched(now)
end sub

' Enqueues the reserved App Launched event. It carries the device/app fields as its data,
' mirroring the mobile SDKs (these also ride the batch meta header). Built directly rather
' than through recordEvent so it bypasses the reserved-name check.
sub ctRecordAppLaunched(now as integer)
    name = CleverTapConstants().APP_LAUNCHED_EVENT_NAME
    ' A full opt-out stops this one too. Marking it as recorded keeps the SDK from trying
    ' again for every event that follows.
    if not ctPrivacyAllows("event", name) then
        m.appLaunchRecorded = true
        return
    end if

    m.queue.enqueueEvent(CleverTapBuildEvent(name, m.appFields, m.session.meta(), now))
    m.appLaunchRecorded = true
    CleverTapLogInfo("event recorded: " + name)
end sub

function ctLoadIdentityCache() as object
    raw = m.storage.read(m.identityCacheKey)
    if raw = invalid then return {}
    parsed = ParseJson(raw)
    if parsed = invalid then return {}
    return parsed
end function

sub ctSaveIdentityCache(cache as object)
    m.storage.write(m.identityCacheKey, FormatJson(cache))
end sub

' Warns at startup when the registry is nearly full.
'
' A Roku app gets one 32K registry, counted after compression, and the SDK shares it with
' the channel it is built into. When the room runs out the SDK cannot save queued items,
' and neither can the channel. The number is logged so an integrator can see the cause
' during development instead of guessing later.
sub ctWarnIfRegistryLow()
    if not m.storage.DoesExist("spaceAvailable") then return

    left = m.storage.spaceAvailable()
    CleverTapLogDebug("registry space left: " + left.ToStr() + " bytes of 32K")
    if left < 4096 then
        CleverTapLogError("only " + left.ToStr() + " bytes are left in this app's 32K registry. Recorded events may not survive a restart. The registry is shared with the channel, so check what else is stored there.")
    end if
end sub

' --- flush scheduling ---

' Flush now if a full batch has built up, otherwise wait out the debounce window.
sub ctMaybeFlush()
    CleverTapLogDebug("items in queue: " + m.queue.count().ToStr())

    ' A send failed and a retry is already waiting. m.failureCount is above zero only while
    ' that is true. Sending now, or restarting the timer, would cut the backoff short. The
    ' delay would go back to one second every time an item is recorded. The backoff would
    ' never be waited out.
    '
    ' This item does not need its own attempt. It waits in the queue. The retry that is
    ' already waiting sends it in the same batch.
    if m.failureCount > 0 then
        CleverTapLogDebug("a retry is already waiting, this item goes out with it")
        return
    end if

    if m.queue.count() >= CleverTapConstants().MAX_BATCH_SIZE then
        CleverTapLogDebug("a full batch has built up, sending now")
        ctFlush()
    else
        ctScheduleFlush()
    end if
end sub

' (Re)start the 1s debounce timer.
sub ctScheduleFlush()
    if m.muted or not m.started then return
    m.timer.control = "stop"
    m.timer.duration = 1
    m.timer.control = "start"
end sub

' Wait longer before retrying, growing the delay with each consecutive failure.
sub ctScheduleRetry()
    if m.muted or not m.started then return
    delay = CleverTapBackoffSeconds(m.failureCount)
    CleverTapLogInfo("sending again in " + delay.ToStr() + "s, failures in a row: " + m.failureCount.ToStr())
    m.timer.control = "stop"
    m.timer.duration = delay
    m.timer.control = "start"
end sub

' Takes no argument on purpose. A field watcher may be declared without one, and the timer
' carries nothing worth reading.
sub ctOnFlushTimer()
    ctFlush()
end sub

' Hand the next batch to the task node, unless one is already in flight, we're muted, or
' there's nothing to send.
sub ctFlush()
    if not m.started or m.muted or m.inFlight then return
    if m.queue.isEmpty() then return

    batch = m.queue.nextBatch(CleverTapConstants().MAX_BATCH_SIZE)
    batchItems = batch.items
    stamps = m.meta.stamps()
    meta = CleverTapBuildMetaHeader(m.config, m.deviceId, m.appFields, stamps.firstTs, stamps.lastTs, m.session.firstRequestInSession(), m.arp)
    payload = FormatJson(CleverTapBuildBatch(meta, batchItems))

    ' An empty string means the writer refused the batch. Sending it would post an empty body
    ' that the server cannot read. The batch stays queued, and the next save takes out the
    ' entry that cannot be written, so the following attempt has a batch that can be sent.
    if payload = "" then
        CleverTapLogError("this batch cannot be written as JSON, so it was not sent. It stays queued.")
        return
    end if

    ' Kept so the line logged when the server replies can name the same items again.
    m.inFlightDescription = CleverTapDescribeBatch(batchItems)
    ' The highest sequence number this batch took from each queue. Kept until the server
    ' replies, because removeSent needs both numbers. Only one batch is ever on its way, so
    ' one copy is enough.
    m.inFlightProfileSeq = batch.profileSeq
    m.inFlightEventSeq = batch.eventSeq
    CleverTapLogInfo("sending to CleverTap: " + m.inFlightDescription)
    CleverTapLogDebug("payload is " + Len(payload).ToStr() + " bytes")

    m.inFlight = true
    m.task.request = {
        config: m.config
        payload: payload
        cachedRedirect: m.cachedRedirect
    }
    m.task.control = "RUN"
end sub

' --- upload result ---

sub ctOnUploadResult(event as object)
    result = event.GetData()
    m.inFlight = false

    ' Remember a redirect host for next time; a "spiky" host wins when both are present.
    if result.spikyDomain <> invalid and result.spikyDomain <> "" then
        ctCacheRedirect(result.spikyDomain)
    else if result.redirectDomain <> invalid and result.redirectDomain <> "" then
        ctCacheRedirect(result.redirectDomain)
    end if

    ' Server asked us to stop: drop the queue and stay quiet for the rest of the run.
    if result.mute then
        CleverTapLogError("server asked the SDK to stop sending, queue cleared")
        m.muted = true
        m.queue.clear()
        return
    end if

    if result.success then
        ' The server may assign its own device id, which replaces the local one.
        if result.serverGuid <> invalid and result.serverGuid <> "" then
            m.deviceId = result.serverGuid
            CleverTapDeviceSetId(m.storage, result.serverGuid)
            CleverTapLogInfo("device id is now " + result.serverGuid)
        end if
        ' After the device id is settled, because what the server sent back is held against
        ' the id it replied about.
        ctApplyArp(result.arp)
        m.failureCount = 0
        ' Record the upload time for the meta header (f_ts once, l_ts every time) and mark
        ' this session past its first request so later batches report frs = false.
        m.meta.recordSuccess(ctNow())
        m.session.markFirstRequestSent()
        ' Remove only what actually went out. An item recorded while the upload was running
        ' is left in the queue and goes out next time.
        m.queue.removeSent(m.inFlightProfileSeq, m.inFlightEventSeq)
        ' Success is not logged. The response status line already reports it, and a failure
        ' is logged as an error. So silence after the "sending" line means it worked.
        ' Anything left (a queue bigger than one batch) goes out next.
        if not m.queue.isEmpty() then
            CleverTapLogDebug("items still waiting: " + m.queue.count().ToStr())
            ctScheduleFlush()
        end if
    else
        ' Keep the queue intact and try again after a backoff.
        CleverTapLogError("send failed with status " + result.statusCode.ToStr() + ", will try again: " + m.inFlightDescription)
        m.failureCount = m.failureCount + 1
        ctScheduleRetry()
    end if
end sub

sub ctCacheRedirect(domain as string)
    ' There is no cached host on the first run, so treat a missing one as empty.
    previous = m.cachedRedirect
    if previous = invalid then previous = ""
    if previous <> domain then CleverTapLogDebug("server address is now " + domain)

    m.cachedRedirect = domain
    m.storage.write(m.redirectKey, domain)
end sub

function ctNow() as integer
    return CreateObject("roDateTime").AsSeconds()
end function

' The country of this device, or "" when the device reports none.
'
' The app fields are the one place this is worked out. The key is left out of them when the
' device does not know its country, so a missing key means "unknown" here too. The server
' sees the same value, which is what the phone number check needs.
function ctDeviceCountryCode() as string
    return m.countryCode
end function

' Reads the saved block. Returns an empty map when none is held, so callers never check for
' invalid.
function ctLoadArp() as object
    raw = m.storage.read(m.arpKey)
    if raw = invalid or raw = "" then return {}

    parsed = ParseJson(raw)
    if parsed = invalid or GetInterface(parsed, "ifAssociativeArray") = invalid then
        CleverTapLogDebug("the saved server block could not be read, so it is started again")
        return {}
    end if
    return parsed
end function

' Takes in the block from a reply: holds the list of switched-off events for this run, then
' saves the rest to repeat in later requests.
sub ctApplyArp(arp as dynamic)
    if arp = invalid then return

    m.discardedEvents = CleverTapArpDiscardedEvents(arp)
    if m.discardedEvents.Count() > 0 then
        CleverTapLogDebug("the dashboard has switched off " + m.discardedEvents.Count().ToStr() + " event names, so they are no longer sent")
    end if

    m.arp = CleverTapMergeArp(m.arp, arp)
    m.storage.write(m.arpKey, FormatJson(m.arp))
end sub

' Forgets the block. The values in it belong to one user, so a switch to another user starts
' with none. The mobile SDKs hold a block per user; one key is held here instead, because the
' registry is small and a key per user would never be given back.
sub ctResetArp()
    m.arp = {}
    m.discardedEvents = []
    m.storage.delete(m.arpKey)
end sub

' Sets the attributes the SDK reads off the device rather than from the app: the country and
' the time zone.
'
' Both are sent as profile attributes, not inside the app fields block, because that is where
' the server reads them from. The mobile SDKs put them in the same place.
'
' Either one is left out when the device does not report it. Nothing is sent when the device
' reports neither.
'
' This runs once per launch, at the end of init. A viewer who changes one of these settings
' is followed, because the new value is sent the next time the channel opens.
sub ctPushDeviceProfile()
    if not ctPrivacyAllows("profile", "") then return

    consts = CleverTapConstants()
    fields = {}
    if m.countryCode <> "" then fields[consts.COUNTRY_KEY] = m.countryCode
    if m.timeZone <> "" then fields[consts.TIMEZONE_KEY] = m.timeZone
    if fields.Count() = 0 then return

    m.queue.enqueueProfile(CleverTapBuildProfile(fields, m.session.meta(), ctNow(), m.countryCode))
    CleverTapLogDebug("device profile recorded, country '" + m.countryCode + "', time zone '" + m.timeZone + "'")
end sub
