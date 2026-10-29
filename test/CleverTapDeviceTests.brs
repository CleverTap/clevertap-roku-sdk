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
        "SDK Version": CleverTapSdkRevision(CleverTapConstants().SDK_VERSION)
        "Model": "Roku Express 4K+"
        "Make": "Roku"
        "OS": "Roku"
        "OS Version": "12.5.1"
        "wdt": 1920
        "hgt": 1080
        "locale": "en_US"
        "useIP": false
        "cc": "US"
    }
    t.eq(af, expected, "app fields match expected shape")
    t.isTrue(GetInterface(af["SDK Version"], "ifInt") <> invalid, "SDK Version is a number, not text")

    ' The version is sent as one number. This is the same mapping the other CleverTap SDKs
    ' use, so the values below are taken from released iOS versions.
    t.eq(CleverTapSdkRevision("7.9.0"), 70900, "7.9.0 becomes 70900")
    t.eq(CleverTapSdkRevision("7.8.2"), 70802, "7.8.2 becomes 70802")
    t.eq(CleverTapSdkRevision("7.5.1"), 70501, "7.5.1 becomes 70501")
    t.eq(CleverTapSdkRevision("1.0.0"), 10000, "the first Roku release becomes 10000")
    t.eq(CleverTapSdkRevision("10.11.12"), 101112, "every part keeps its own place")
    t.eq(CleverTapSdkRevision("1.2"), 10200, "a missing patch part counts as zero")

    ' A TV running Roku OS is made by another company. Its own name is sent, not "Roku".
    tcl = CTFakeDeviceInfoAsTV("TCL", "TCL Roku TV")
    t.eq(CleverTapDeviceMake(tcl), "TCL", "a TV reports the company that made it")
    t.eq(CleverTapDeviceModel(tcl), "TCL Roku TV", "a TV reports its own name")

    ' A device that reports no maker and no name falls back to what we can still say.
    bare = CTFakeDeviceInfoAsTV("", "")
    t.eq(CleverTapDeviceMake(bare), "Roku", "an empty maker falls back to Roku")
    t.eq(CleverTapDeviceModel(bare), "8000X", "an empty name falls back to the model code")

    ' A country the device does not know is left out of the app fields, not sent as an empty
    ' value. The mobile SDKs leave it out in the same case.
    unknownCountry = CleverTapDeviceAppFields(CTFakeDeviceInfoWithCountryCode("OT"), CTFakeAppInfo())
    t.isFalse(unknownCountry.DoesExist("cc"), "an unknown country is left out of the app fields")

    ' "OT" means the device does not know the country. It is left out rather than sent as a
    ' country name. An empty value is left out too.
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("OT")), "", "country code OT is not sent")
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("")), "", "empty country code is not sent")

    ' An account opened through a partner names the partner rather than the country. The
    ' partner belongs to one country, so it is read as that country.
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("skyuk")), "GB", "a partner name is read as its country")

    ' Roku writes these names in several letter cases, so the case is not trusted.
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("Telstra")), "AU", "a partner name in another letter case is still read")
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("PLDT")), "PH", "two partners can share one country")

    ' An ordinary country code passes through untouched.
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("MX")), "MX", "a two-letter country code is used as it is")

    ' Roku may add a partner this SDK has not heard of. Its name must not reach the server as
    ' a country, so a value that is not two letters is treated as unknown.
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("newpartner")), "", "an unknown partner name is not sent")
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("U1")), "", "a value with a digit in it is not sent")
    t.eq(CleverTapCountryCode(CTFakeDeviceInfoWithCountryCode("USA")), "", "a three-letter value is not sent")

    ' The time zone comes from the device and is turned into the standard name. Roku uses its
    ' own names. CleverTapTimeZoneTests covers the table that joins the two.
    t.eq(CleverTapDeviceTimeZone(CTFakeDeviceInfo()), "America/Los_Angeles", "the time zone comes from the device")

    ' "tz" is a system key, so it is sent as it is spelled and is not checked as a custom key.
    tzProfile = CleverTapBuildProfile({ "tz": "America/Los_Angeles" }, { s: 1, pg: 1, lsl: 0, f: true }, 1700000000)
    t.eq(tzProfile.profile["tz"], "America/Los_Angeles", "the time zone rides in the profile")

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
