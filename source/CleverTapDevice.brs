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

' Who made the device, for the "Make" field.
'
' Roku sells its own players. Other companies also sell TVs that run Roku OS, such as TCL
' and Hisense. On one of those TVs the maker is TCL, not Roku. The device reports the maker
' as the vendor name.
'
' A Roku-branded player may leave the vendor name empty. "Roku" is then the answer.
function CleverTapDeviceMake(deviceInfo as object) as string
    details = deviceInfo.GetModelDetails()
    if details <> invalid and details.VendorName <> invalid and details.VendorName <> "" then
        return details.VendorName
    end if
    return CleverTapConstants().OS_NAME
end function

' Which device it is, for the "Model" field.
'
' Two names exist for every device. One is a code such as "3810X". The other is the name
' people know, such as "Roku Streaming Stick+". The dashboard shows this value as it is
' given, so the name people know is the useful one.
'
' The code is the answer when the device reports no name.
function CleverTapDeviceModel(deviceInfo as object) as string
    displayName = deviceInfo.GetModelDisplayName()
    if displayName <> invalid and displayName <> "" then
        return displayName
    end if
    return deviceInfo.GetModel()
end function

' Builds the app-fields map the server expects in the batch meta header. deviceInfo is an
' roDeviceInfo and appInfo is an roAppInfo; both are passed in so tests can supply fakes.
'
' reportNetworkInfo says whether the app asked for network details to be reported. It is off
' unless the app turns it on. See CleverTapDeviceNetworkFields for what it adds.
function CleverTapDeviceAppFields(deviceInfo as object, appInfo as object, reportNetworkInfo = false as boolean) as object
    osVersion = deviceInfo.GetOSVersion()
    display = deviceInfo.GetDisplaySize()
    consts = CleverTapConstants()

    fields = {
        "Version": appInfo.GetVersion()
        "Build": appInfo.GetValue("build_version")
        ' A number, not "1.0.0". This is what the dashboard shows as the SDK version of the
        ' profile.
        "SDK Version": CleverTapSdkRevision(consts.SDK_VERSION)
        "Model": CleverTapDeviceModel(deviceInfo)
        "Make": CleverTapDeviceMake(deviceInfo)
        "OS": consts.OS_NAME
        "OS Version": osVersion.major + "." + osVersion.minor + "." + osVersion.revision
        "wdt": display.w
        "hgt": display.h
        "locale": deviceInfo.GetCurrentLocale()
        ' Whether the server may work out where the viewer is from the address the request
        ' came from. It is false unless the app turns network reporting on.
        "useIP": reportNetworkInfo
    }

    ' The country is sent twice, which is what the mobile SDKs do. It is an app field here,
    ' and the node also sets it as a profile attribute. The dashboard reads the profile
    ' attribute. A country the device does not know is left out of both.
    country = CleverTapCountryCode(deviceInfo)
    if country <> "" then fields[consts.COUNTRY_KEY] = country

    if reportNetworkInfo then
        networkFields = CleverTapDeviceNetworkFields(deviceInfo)
        for each key in networkFields
            fields[key] = networkFields[key]
        end for
    end if

    return fields
end function

' The network details, for an app that asked for them.
'
' Nothing here is sent unless the app calls enableDeviceNetworkInfoReporting(true). A viewer
' did not ask to have their network described. An app that needs it has to ask for it, and
' has to be able to say why.
'
' The mobile SDKs also report the mobile network the phone is on. A Roku device has no
' mobile radio, so there is nothing of the kind to report here.
function CleverTapDeviceNetworkFields(deviceInfo as object) as object
    ' Roku answers "WiFiConnection", "WiredConnection", or "" when there is no connection.
    ' A TV joined by cable reports false here. That is a real answer, not a missing one.
    return { "wifi": (deviceInfo.GetConnectionType() = "WiFiConnection") }
end function

' The country of this device as a two-letter ISO code, or "" when it is not known.
'
' The value comes from the Roku account's store, not from where the device is. Roku returns
' three kinds of value from it.
'
' A two-letter country code, such as "US". That is the common case and it is used as it is.
'
' The name of a partner, such as "skyuk", when the account was opened through one. Each
' partner belongs to one country, so the name is read as that country.
'
' "OT", which Roku calls "Rest of World". It is not a country and it is not sent. Sending it
' would show a country named "OT" on the profile page.
'
' Anything that is not one of those three is treated as unknown. Roku may add a partner later
' and this SDK would not know its name yet. An unknown name must not reach the server as a
' country.
function CleverTapCountryCode(deviceInfo as object) as string
    reported = deviceInfo.GetCountryCode()
    if reported = invalid or reported = "" then return ""

    consts = CleverTapConstants()
    partner = consts.PARTNER_COUNTRY_CODES[LCase(reported)]
    if partner <> invalid then return partner

    if reported = consts.UNKNOWN_COUNTRY_CODE then return ""
    if not CleverTapIsCountryCode(reported) then return ""
    return reported
end function

' The time zone the viewer has chosen, written the way the rest of the world writes it.
' Returns "" when the device reports no zone. Returns "" when the zone is not a name Roku
' documents.
'
' Roku uses its own names. The server cannot read them. CleverTapIanaTimeZone turns a Roku name
' into the standard one. Read the comment at the top of CleverTapTimeZone.brs for the reason.
'
' A name that cannot be turned into a standard one is reported and dropped. Sending it would
' put a wrong time zone on the profile. No time zone at all is the better of the two.
function CleverTapDeviceTimeZone(deviceInfo as object) as string
    zone = deviceInfo.GetTimeZone()
    if zone = invalid or zone = "" then return ""

    mapped = CleverTapIanaTimeZone(zone)
    if mapped = "" then
        CleverTapLogError("the device reports time zone '" + zone + "', which this SDK does not know. No time zone was sent.")
        return ""
    end if
    return mapped
end function

' True when the text is two letters, which is the shape of an ISO country code.
function CleverTapIsCountryCode(text as string) as boolean
    if Len(text) <> 2 then return false

    upper = UCase(text)
    for i = 0 to 1
        letter = Mid(upper, i + 1, 1)
        if letter < "A" or letter > "Z" then return false
    end for
    return true
end function
