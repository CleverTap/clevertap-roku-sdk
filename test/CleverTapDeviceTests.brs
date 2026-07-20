function CleverTapDeviceTests(t as object)
    ' The device id is generated once and then reused on every later read.
    storage = CleverTapFakeStorage()
    first = CleverTapDeviceGetId(storage)
    second = CleverTapDeviceGetId(storage)
    t.isTrue(first <> "" and first <> invalid, "device id is generated")
    t.eq(second, first, "device id is stable across reads")

    ' An explicitly set id (server- or login-assigned) replaces the stored one.
    CleverTapDeviceSetId(storage, "server-guid-123")
    t.eq(CleverTapDeviceGetId(storage), "server-guid-123", "set id overrides stored id")

    ' The app-fields block has the exact keys and values the server expects.
    af = CleverTapDeviceAppFields(CTFakeDeviceInfo(), CTFakeAppInfo())
    expected = {
        "Version": "1.2.0"
        "Build": "42"
        "Model": "8000X"
        "Make": "Roku"
        "OS": "Roku"
        "OS Version": "12.5.1"
        "wdt": 1920
        "hgt": 1080
        "cc": "US"
        "locale": "en_US"
        "useIP": false
    }
    t.eq(af, expected, "app fields match expected shape")

    ' Credentials: values in the init() config win over the manifest.
    manifestInfo = CTFakeManifestAppInfo({
        "clevertap_account_id": "MANIFEST-ACCT"
        "clevertap_token": "MANIFEST-TOKEN"
        "clevertap_region": "eu1"
    })
    fromConfig = CleverTapResolveCredentials({ accountId: "CFG-ACCT", token: "CFG-TOKEN", region: "in1" }, manifestInfo)
    t.eq(fromConfig.accountId, "CFG-ACCT", "config account id wins over manifest")
    t.eq(fromConfig.token, "CFG-TOKEN", "config token wins over manifest")
    t.eq(fromConfig.region, "in1", "config region wins over manifest")

    ' Credentials: with an empty config, everything falls back to the manifest.
    fromManifest = CleverTapResolveCredentials({}, manifestInfo)
    t.eq(fromManifest.accountId, "MANIFEST-ACCT", "account id falls back to manifest")
    t.eq(fromManifest.token, "MANIFEST-TOKEN", "token falls back to manifest")
    t.eq(fromManifest.region, "eu1", "region falls back to manifest")

    ' A proxy domain is code-only and passes straight through.
    withProxy = CleverTapResolveCredentials({ accountId: "A", token: "B", proxyDomain: "proxy.example.com" }, manifestInfo)
    t.eq(withProxy.proxyDomain, "proxy.example.com", "proxy domain comes from config")

    ' Missing everywhere resolves to empty strings the caller can check.
    empty = CleverTapResolveCredentials({}, CTFakeManifestAppInfo({}))
    t.eq(empty.accountId, "", "absent account id is empty")
    t.eq(empty.proxyDomain, "", "absent proxy domain is empty")
end function
