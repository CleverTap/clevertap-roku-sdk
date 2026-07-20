' Pure networking decisions, split out from the Task node so they can be tested without a
' device: which host to talk to, whether the one-time redirect lookup is needed, how long
' to wait before a retry, and how to read the server's response headers and body.

' Works out the upload host and whether the /hello redirect lookup is required.
'
' Rules (highest priority first):
'   - an explicit proxy domain is used as-is;
'   - a region maps straight to "{region}.{base domain}";
'   - a redirect host cached from an earlier lookup is reused;
'   - otherwise we must do the /hello lookup once to learn the host.
function CleverTapResolveDomain(config as object, cachedRedirect as dynamic) as object
    consts = CleverTapConstants()

    if config.proxyDomain <> invalid and config.proxyDomain <> "" then
        return { domain: config.proxyDomain, needsHandshake: false }
    end if

    if config.region <> invalid and config.region <> "" then
        return { domain: config.region + "." + consts.API_DOMAIN, needsHandshake: false }
    end if

    if cachedRedirect <> invalid and cachedRedirect <> "" then
        return { domain: cachedRedirect, needsHandshake: false }
    end if

    return { domain: invalid, needsHandshake: true }
end function

' Seconds to wait before the next upload attempt, growing with each consecutive failure so
' we back off a struggling network instead of hammering it. Doubles from 1s and caps at 60s.
function CleverTapBackoffSeconds(failureCount as integer) as integer
    if failureCount <= 1 then return 1
    delay = 1
    for i = 1 to failureCount - 1
        delay = delay * 2
        if delay >= 60 then return 60
    end for
    return delay
end function

' Pulls the fields we care about out of the response headers, tolerant of header-name
' casing. Returns redirect host, spiky (high-throughput) redirect host, and the mute flag
' that tells us to stop sending.
function CleverTapParseResponseHeaders(headers as object) as object
    consts = CleverTapConstants()
    result = { redirectDomain: invalid, spikyDomain: invalid, mute: false }
    if headers = invalid then return result

    for each key in headers
        lower = LCase(key)
        if lower = LCase(consts.HEADER_REDIRECT_DOMAIN) then
            result.redirectDomain = headers[key]
        else if lower = LCase(consts.HEADER_SPIKY_REDIRECT_DOMAIN) then
            result.spikyDomain = headers[key]
        else if lower = LCase(consts.HEADER_MUTE) then
            result.mute = (headers[key] = "1" or LCase("" + headers[key]) = "true")
        end if
    end for

    return result
end function

' The server may return a device id ("g") that should replace the local one. Returns the
' id string, or invalid if the body has none.
function CleverTapExtractServerGuid(responseBody as dynamic) as dynamic
    if responseBody = invalid or responseBody = "" then return invalid
    parsed = ParseJson(responseBody)
    if parsed = invalid then return invalid
    if GetInterface(parsed, "ifAssociativeArray") = invalid then return invalid
    if parsed.DoesExist("g") then return parsed["g"]
    return invalid
end function
