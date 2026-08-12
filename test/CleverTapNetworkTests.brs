function CleverTapNetworkTests(t as object)
    ' A proxy domain wins and skips the redirect lookup.
    r1 = CleverTapResolveDomain({ proxyDomain: "proxy.example.com", region: "in1" }, invalid)
    t.eq(r1.domain, "proxy.example.com", "proxy domain is used as-is")
    t.isFalse(r1.needsHandshake, "proxy domain skips handshake")

    ' A region maps to a host and skips the lookup.
    r2 = CleverTapResolveDomain({ region: "in1" }, invalid)
    t.eq(r2.domain, "in1.clevertap-prod.com", "region maps to host")
    t.isFalse(r2.needsHandshake, "region skips handshake")

    ' No region/proxy but a cached redirect: reuse it, no lookup.
    r3 = CleverTapResolveDomain({}, "in1.clevertap-prod.com")
    t.eq(r3.domain, "in1.clevertap-prod.com", "cached redirect is reused")
    t.isFalse(r3.needsHandshake, "cached redirect skips handshake")

    ' Nothing supplied: the one-time lookup is required.
    r4 = CleverTapResolveDomain({}, invalid)
    t.isTrue(r4.needsHandshake, "no region/proxy/cache needs handshake")

    ' Backoff doubles from 1s and caps at 60s.
    t.eq(CleverTapBackoffSeconds(1), 1, "first retry waits 1s")
    t.eq(CleverTapBackoffSeconds(2), 2, "second retry waits 2s")
    t.eq(CleverTapBackoffSeconds(3), 4, "third retry waits 4s")
    t.eq(CleverTapBackoffSeconds(4), 8, "fourth retry waits 8s")
    t.eq(CleverTapBackoffSeconds(20), 60, "backoff caps at 60s")

    ' Response headers are read regardless of casing.
    headers = { "x-wzrk-rd": "in1.clevertap-prod.com", "X-WZRK-MUTE": "1" }
    parsed = CleverTapParseResponseHeaders(headers)
    t.eq(parsed.redirectDomain, "in1.clevertap-prod.com", "redirect header is read case-insensitively")
    t.isTrue(parsed.mute, "mute header of 1 is true")

    noMute = CleverTapParseResponseHeaders({ "X-WZRK-RD": "eu1.clevertap-prod.com" })
    t.isFalse(noMute.mute, "absent mute header is false")

    ' Server-assigned device id is pulled from the body when present.
    t.eq(CleverTapExtractServerGuid("{""g"":""server-guid""}"), "server-guid", "server guid is extracted")
    t.eq(CleverTapExtractServerGuid("{""x"":1}"), invalid, "no g means no server guid")
    t.eq(CleverTapExtractServerGuid("not json"), invalid, "bad body yields no guid")
end function
