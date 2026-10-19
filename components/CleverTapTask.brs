' Runs on its own thread so network calls never block the render thread. The main node
' fills in m.top.request and sets control = "RUN"; this uploads one batch and writes the
' outcome to m.top.response, which the main node observes.
'
' The pure decisions (which host, how to read the response) live in CleverTapNetwork so
' they can be tested off-device; this file is just the roUrlTransfer plumbing around them.

sub init()
    m.top.functionName = "ctRunUpload"
end sub

' Entry point on the task thread. Resolves the host (doing the one-time /hello lookup only
' when needed), POSTs the batch, and reports the result.
sub ctRunUpload()
    req = m.top.request
    config = req.config
    ' Each SceneGraph thread has its own logger state, so the level is set again here.
    CleverTapLogSetLevel(config.logLevel)

    resolved = CleverTapResolveDomain(config, req.cachedRedirect)
    domain = resolved.domain
    redirectFromHandshake = invalid

    ' No region/proxy/cached host: ask /hello where to send, then remember it.
    if resolved.needsHandshake then
        CleverTapLogDebug("no server address known yet, asking " + CleverTapConstants().HANDSHAKE_URL)
        hello = ctHttpRequest("GET", CleverTapConstants().HANDSHAKE_URL, invalid, ctRequestHeaders(config))
        if hello.code = 200 then
            headers = CleverTapParseResponseHeaders(hello.headers)
            redirectFromHandshake = headers.redirectDomain
            domain = redirectFromHandshake
        end if
        ' Handshake did not give us a host: report failure so the caller retries later.
        if domain = invalid or domain = "" then
            CleverTapLogError("handshake returned no server address, status " + hello.code.ToStr())
            m.top.response = ctFailure(req.sentCount)
            return
        end if
        CleverTapLogDebug("handshake returned host " + domain)
    end if

    url = CleverTapBuildUploadUrl(domain, config.accountId, ctNowSeconds())
    CleverTapLogDebug("POST " + url)
    CleverTapLogDebug("payload " + req.payload)
    post = ctHttpRequest("POST", url, req.payload, ctRequestHeaders(config))
    CleverTapLogDebug("response status " + post.code.ToStr() + ", body " + post.body)

    parsed = CleverTapParseResponseHeaders(post.headers)
    ' Prefer a redirect learned from the upload; fall back to the handshake's.
    redirect = parsed.redirectDomain
    if redirect = invalid then redirect = redirectFromHandshake

    m.top.response = {
        success: (post.code = 200)
        statusCode: post.code
        sentCount: req.sentCount
        redirectDomain: redirect
        spikyDomain: parsed.spikyDomain
        mute: parsed.mute
        serverGuid: CleverTapExtractServerGuid(post.body)
    }
end sub

' One HTTP call. Returns { code, headers, body }.
'
' code is the HTTP status when the server replied. It is a negative curl error number when
' the request never got that far, for example -6 when the host name could not be turned into
' an address. It is -1 when the request could not be started, or when it ran past 30 seconds.
function ctHttpRequest(method as string, url as string, body as dynamic, headers as object) as object
    port = CreateObject("roMessagePort")
    transfer = CreateObject("roUrlTransfer")
    transfer.SetMessagePort(port)
    transfer.SetUrl(url)
    transfer.SetHeaders(headers)
    ' HTTPS on Roku needs the system CA bundle.
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()

    started = false
    if method = "POST" then
        transfer.SetRequest("POST")
        started = transfer.AsyncPostFromString(body)
    else
        started = transfer.AsyncGetToString()
    end if
    if not started then
        CleverTapLogError("could not start the " + method + " request to " + url)
        return { code: -1, headers: {}, body: "" }
    end if

    msg = wait(30000, port)
    if type(msg) = "roUrlEvent" then
        code = msg.GetResponseCode()
        ' A code below zero is not an HTTP status. It is a curl error number, and the number
        ' alone says nothing. For example -6 means the device could not turn the host name
        ' into an address. The device can describe the error, so log that description.
        if code < 0 then
            CleverTapLogError(method + " to " + url + " failed: " + msg.GetFailureReason() + " (code " + code.ToStr() + ")")
        end if
        return { code: code, headers: msg.GetResponseHeaders(), body: msg.GetString() }
    end if

    ' Timed out; cancel and report a transport failure.
    CleverTapLogError("the " + method + " request to " + url + " timed out after 30s")
    transfer.AsyncCancel()
    return { code: -1, headers: {}, body: "" }
end function

function ctRequestHeaders(config as object) as object
    consts = CleverTapConstants()
    headers = {}
    headers[consts.HEADER_ACCOUNT_ID] = config.accountId
    headers[consts.HEADER_TOKEN] = config.token
    headers[consts.HEADER_CONTENT_TYPE] = consts.CONTENT_TYPE_JSON
    return headers
end function

function ctFailure(sentCount as integer) as object
    return {
        success: false
        statusCode: -1
        sentCount: sentCount
        redirectDomain: invalid
        spikyDomain: invalid
        mute: false
        serverGuid: invalid
    }
end function

function ctNowSeconds() as integer
    return CreateObject("roDateTime").AsSeconds()
end function
