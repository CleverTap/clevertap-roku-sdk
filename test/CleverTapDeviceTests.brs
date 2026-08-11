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
end function
