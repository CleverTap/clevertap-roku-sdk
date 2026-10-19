' Device identity and the app-fields ("af") block that rides on every upload.
'
' Each install gets one anonymous device id (a GUID). We generate it once, keep it in
' storage, and reuse it on every launch so the server recognises the same device. The
' server can also hand back its own id (the "g" field in a response), which then replaces
' the local one; onUserLogin can swap it too when switching users.

' Registry key the device id lives under. (BrightScript has no file-level constants, so it
' is a function returning the literal.)
function CleverTapDeviceIdKey() as string
    return "deviceId"
end function

' Returns the persisted device id, generating and saving a fresh GUID the first time.
' Passing the same storage always yields the same id.
function CleverTapDeviceGetId(storage as object) as string
    existing = storage.read(CleverTapDeviceIdKey())
    if existing <> invalid and existing <> "" then return existing

    newId = CreateObject("roDeviceInfo").GetRandomUUID()
    storage.write(CleverTapDeviceIdKey(), newId)
    return newId
end function

' Overwrites the stored device id. Used when the server assigns an id or when a user
' switch points us at a different id.
sub CleverTapDeviceSetId(storage as object, deviceId as string)
    storage.write(CleverTapDeviceIdKey(), deviceId)
end sub

' Resolves the SDK credentials from the config the app passed to init(), falling back to
' the Roku manifest for any value the app left out. This lets a channel either configure the
' SDK in code or bake the keys into its manifest (clevertap_account_id / _token / _region /
' _log_level).
' appInfo is an roAppInfo (passed in so tests can supply a fake). Missing values come back
' as "" so callers can check for them.
function CleverTapResolveCredentials(config as object, appInfo as object) as object
    consts = CleverTapConstants()
    if config = invalid then config = {}

    creds = {
        accountId: CleverTapCredentialValue(config, "accountId", appInfo, consts.MANIFEST_ACCOUNT_ID)
        token: CleverTapCredentialValue(config, "token", appInfo, consts.MANIFEST_TOKEN)
        region: CleverTapCredentialValue(config, "region", appInfo, consts.MANIFEST_REGION)
        ' How much the SDK logs. "" means the logger keeps its own default.
        logLevel: CleverTapCredentialValue(config, "logLevel", appInfo, consts.MANIFEST_LOG_LEVEL)
        proxyDomain: ""
    }
    ' Proxy domain is code-only; there's no manifest fallback for it.
    if config.DoesExist("proxyDomain") and config.proxyDomain <> invalid then creds.proxyDomain = config.proxyDomain
    return creds
end function

' Prefers the value from the init() config; if absent or blank, reads the manifest key.
function CleverTapCredentialValue(config as object, key as string, appInfo as object, manifestKey as string) as string
    if config.DoesExist(key) and config[key] <> invalid and config[key] <> "" then return config[key]
    fromManifest = appInfo.GetValue(manifestKey)
    if fromManifest <> invalid then return fromManifest
    return ""
end function

' Builds the app-fields map the server expects in the batch meta header. deviceInfo is an
' roDeviceInfo and appInfo is an roAppInfo; both are passed in so tests can supply fakes.
function CleverTapDeviceAppFields(deviceInfo as object, appInfo as object) as object
    osVersion = deviceInfo.GetOSVersion()
    display = deviceInfo.GetDisplaySize()
    consts = CleverTapConstants()

    return {
        "Version": appInfo.GetVersion()
        "Build": appInfo.GetValue("build_version")
        "Model": deviceInfo.GetModel()
        "Make": consts.OS_NAME
        "OS": consts.OS_NAME
        "OS Version": osVersion.major + "." + osVersion.minor + "." + osVersion.revision
        "wdt": display.w
        "hgt": display.h
        "cc": deviceInfo.GetCountryCode()
        "locale": deviceInfo.GetCurrentLocale()
        ' We never let the server infer location from the request IP.
        "useIP": false
    }
end function
