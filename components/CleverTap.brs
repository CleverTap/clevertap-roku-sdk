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
    if config = invalid then
        m.started = false
        return
    end if

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
    m.cachedRedirect = m.storage.read(m.redirectKey)
    m.failureCount = 0
    m.muted = false
    m.inFlight = false

    ' Child that runs roUrlTransfer on its own thread; we watch its response field.
    m.task = m.top.CreateChild("CleverTapTask")
    m.task.observeField("response", "ctOnUploadResult")

    ' Debounce timer: recording an event (re)starts it, so a burst of events uploads once.
    m.timer = m.top.CreateChild("Timer")
    m.timer.repeat = false
    m.timer.observeField("fire", "ctOnFlushTimer")

    m.started = true
    ' Send anything left over from a previous run (for example events queued while offline).
    ctScheduleFlush()
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
    m.session.ensure(now)
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
    m.session.ensure(now)
    m.queue.enqueueEvent(CleverTapBuildChargedEvent(details, items, m.session.meta(), now))
    ctMaybeFlush()
end function

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
