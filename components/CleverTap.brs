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
        if m.config.accountId = "" or m.config.token = "" then
            print "CleverTap: missing account id or token; SDK inactive"
            return
        end if

        ' Everything durable is namespaced per account so two accounts never collide.
        m.storage = CleverTapStorage("clevertap_" + m.config.accountId)
        m.deviceId = CleverTapDeviceGetId(m.storage)
        m.appFields = CleverTapDeviceAppFields(CreateObject("roDeviceInfo"), appInfo)
        m.session = CleverTapSession(m.storage)
        m.queue = CleverTapQueue(m.storage)
        m.queue.load()

        m.redirectKey = "redirectDomain"
        m.identityCacheKey = "identityCache"
        m.identifiedKey = "identified"
        m.cachedRedirect = m.storage.read(m.redirectKey)
        m.failureCount = 0
        m.muted = false
        m.inFlight = false
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
        ' Fire App Launched for this launch (the mobile SDKs do the same on cold start), then
        ' send it alongside anything left over from a previous run (e.g. events queued offline).
        ctEnsureSession(ctNow())
        ctScheduleFlush()
    end if
end function

' Records a custom event. args is [name, props]; props is optional.
function recordEvent(args as object) as void
    if not m.started then return

    name = args[0]
    props = invalid
    if args.Count() > 1 then props = args[1]

    check = CleverTapValidator().validateEventName(name)
    if not check.valid then
        print "CleverTap: " + check.message
        return
    end if

    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueEvent(CleverTapBuildEvent(check.value, props, m.session.meta(), now))
    ctMaybeFlush()
end function

' Records a purchase. args is [details, items]; details holds Amount etc., items is the line
' items array. Both ride in a reserved "Charged" event.
function recordChargedEvent(args as object) as void
    if not m.started then return

    details = args[0]
    items = invalid
    if args.Count() > 1 then items = args[1]

    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueEvent(CleverTapBuildChargedEvent(details, items, m.session.meta(), now))
    ctMaybeFlush()
end function

' Sets attributes on the current user. args is [profileFields], a map of attribute
' name -> value. Goes into the profile queue so it ships ahead of events on the next flush.
function profilePush(args as object) as void
    if not m.started then return

    fields = args[0]
    if fields = invalid then return

    now = ctNow()
    ctEnsureSession(now)
    m.queue.enqueueProfile(CleverTapBuildProfile(fields, m.session.meta(), now))
    ctMaybeFlush()
end function

' Identifies a user and sets their attributes. args is [profileFields], where the map may
' carry an identity field (Identity, Email, or Phone). Depending on whether that identity is
' new, returning, or already active, this may switch to a different device id first.
function onUserLogin(args as object) as void
    if not m.started then return

    input = args[0]
    if input = invalid then return

    cache = ctLoadIdentityCache()
    identified = (m.storage.read(m.identifiedKey) = "1")
    ' Candidate id used only if this turns out to be a brand-new user.
    newId = CreateObject("roDeviceInfo").GetRandomUUID()

    decision = CleverTapResolveLogin(input, m.deviceId, identified, cache, newId)

    if decision.action = "switch" then
        ' Moving to a different user: drop the previous user's unsent items so they can't be
        ' attributed to this one, and start a fresh session under the new id.
        m.queue.clear()
        m.session.reset()
        m.deviceId = decision.deviceId
        CleverTapDeviceSetId(m.storage, decision.deviceId)
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
    ctMaybeFlush()
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
    if (not m.appLaunchRecorded) or startedNew then ctRecordAppLaunched(now)
end sub

' Enqueues the reserved App Launched event. It carries the device/app fields as its data,
' mirroring the mobile SDKs (these also ride the batch meta header). Built directly rather
' than through recordEvent so it bypasses the reserved-name check.
sub ctRecordAppLaunched(now as integer)
    m.queue.enqueueEvent(CleverTapBuildEvent(CleverTapConstants().APP_LAUNCHED_EVENT_NAME, m.appFields, m.session.meta(), now))
    m.appLaunchRecorded = true
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

' --- flush scheduling ---

' Flush now if a full batch has built up, otherwise wait out the debounce window.
sub ctMaybeFlush()
    if m.queue.count() >= CleverTapConstants().MAX_BATCH_SIZE then
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
    m.timer.control = "stop"
    m.timer.duration = CleverTapBackoffSeconds(m.failureCount)
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

    batchItems = m.queue.nextBatch(CleverTapConstants().MAX_BATCH_SIZE)
    meta = CleverTapBuildMetaHeader(m.config, m.deviceId, m.appFields)
    payload = FormatJson(CleverTapBuildBatch(meta, batchItems))

    m.inFlight = true
    m.task.request = {
        config: m.config
        payload: payload
        sentCount: batchItems.Count()
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
        m.muted = true
        m.queue.clear()
        return
    end if

    if result.success then
        ' The server may assign its own device id, which replaces the local one.
        if result.serverGuid <> invalid and result.serverGuid <> "" then
            m.deviceId = result.serverGuid
            CleverTapDeviceSetId(m.storage, result.serverGuid)
        end if
        m.failureCount = 0
        ' Remove only what actually went out, so items recorded mid-upload survive.
        m.queue.removeSent(result.sentCount)
        ' Anything left (a queue bigger than one batch) goes out next.
        if not m.queue.isEmpty() then ctScheduleFlush()
    else
        ' Keep the queue intact and try again after a backoff.
        m.failureCount = m.failureCount + 1
        ctScheduleRetry()
    end if
end sub

sub ctCacheRedirect(domain as string)
    m.cachedRedirect = domain
    m.storage.write(m.redirectKey, domain)
end sub

function ctNow() as integer
    return CreateObject("roDateTime").AsSeconds()
end function
