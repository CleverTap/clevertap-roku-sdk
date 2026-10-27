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
        m.appFields = CleverTapDeviceAppFields(CreateObject("roDeviceInfo"), appInfo)
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
        ' Fire App Launched for this launch (the mobile SDKs do the same on cold start), then
        ' send it alongside anything left over from a previous run (e.g. events queued offline).
        ctEnsureSession(ctNow())
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

    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueProfile(CleverTapBuildProfile(fields, m.session.meta(), now))
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
        m.deviceId = decision.deviceId
        CleverTapDeviceSetId(m.storage, decision.deviceId)
        CleverTapLogInfo("device id is now " + decision.deviceId)
    end if

    ' Remember the identity -> id mapping and that the device is now identified.
    if decision.cacheKey <> invalid then
        cache[decision.cacheKey] = decision.deviceId
        ctSaveIdentityCache(cache)
        m.storage.write(m.identifiedKey, "1")
    end if

    ' Push the supplied attributes under the (possibly new) id. On a switch the session was
    ' just reset, so ctEnsureSession starts a fresh one and fires App Launched into the now
    ' empty queue ahead of this profile - matching the mobile clear -> App Launched -> profile
    ' order.
    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueProfile(CleverTapBuildProfile(input, m.session.meta(), now))
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
    m.queue.enqueueEvent(CleverTapBuildEvent(CleverTapConstants().APP_LAUNCHED_EVENT_NAME, m.appFields, m.session.meta(), now))
    m.appLaunchRecorded = true
    CleverTapLogInfo("event recorded: " + CleverTapConstants().APP_LAUNCHED_EVENT_NAME)
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

sub ctOnFlushTimer(event as object)
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
    meta = CleverTapBuildMetaHeader(m.config, m.deviceId, m.appFields, stamps.firstTs, stamps.lastTs, m.session.firstRequestInSession())
    payload = FormatJson(CleverTapBuildBatch(meta, batchItems))
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
