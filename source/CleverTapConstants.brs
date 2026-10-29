' Central place for the fixed values the SDK needs: server domains, endpoints, header
' names, batch limits, and the registry/manifest keys we read and write. Kept in one
' function so callers grab a single map instead of scattering magic strings around.
function CleverTapConstants() as object
    return {
        ' SDK version reported to the server (the "t" query param on uploads).
        SDK_VERSION: "1.0.0"

        ' Reported as the "os" query param and inside the app-fields block.
        OS_NAME: "Roku"

        ' What roDeviceInfo.GetCountryCode() returns when it does not know the country. Roku
        ' calls it "Rest of World". It is not a country, so we do not send it.
        UNKNOWN_COUNTRY_CODE: "OT"

        ' Some Roku accounts are opened through a partner rather than through the Roku store.
        ' GetCountryCode() then names the partner instead of the country. The names are
        ' listed in Roku's documentation for ifDeviceInfo. Each one belongs to one country,
        ' so each is read as that country.
        '
        ' The key is the name in lower case. The name is lowered before it is looked up here,
        ' because Roku writes these in several letter cases.
        PARTNER_COUNTRY_CODES: {
            "econet": "ZW"
            "globe": "PH"
            "pldt": "PH"
            "skyde": "DE"
            "skyie": "IE"
            "skyit": "IT"
            "skyuk": "GB"
            "telstra": "AU"
        }

        ' Base domain for the whole platform. A region turns into "{region}.{API_DOMAIN}".
        API_DOMAIN: "clevertap-prod.com"

        ' One-time redirect lookup, only used when the app gives us no region or proxy.
        HANDSHAKE_URL: "https://clevertap-prod.com/hello"

        ' Path we POST event/profile batches to.
        UPLOAD_PATH: "/a1"

        ' Request headers the server expects.
        HEADER_ACCOUNT_ID: "X-CleverTap-Account-Id"
        HEADER_TOKEN: "X-CleverTap-Token"
        HEADER_CONTENT_TYPE: "Content-Type"
        CONTENT_TYPE_JSON: "application/json"

        ' Response headers the server may send back.
        HEADER_REDIRECT_DOMAIN: "X-WZRK-RD"
        HEADER_SPIKY_REDIRECT_DOMAIN: "X-WZRK-SPIKY-RD"
        HEADER_MUTE: "X-WZRK-MUTE"

        ' Largest number of items we send in a single upload; bigger queues go out in
        ' back-to-back batches.
        MAX_BATCH_SIZE: 49

        ' A session ends after this many minutes of inactivity; the next event starts a
        ' fresh one.
        SESSION_LENGTH_MINS: 20

        ' Reserved event name for purchases recorded via recordChargedEvent.
        CHARGED_EVENT_NAME: "Charged"

        ' Reserved event the SDK fires itself at the start of every session (app launch,
        ' session timeout, or user switch), mirroring the mobile SDKs.
        APP_LAUNCHED_EVENT_NAME: "App Launched"

        ' How many recent log lines the SDK keeps in memory. The sample channel can show
        ' these on screen. A UI test reads them from there.
        LOG_BUFFER_LINES: 50

        ' Longest a single log line may be once it is stored in memory. The debug console
        ' still receives the whole line.
        LOG_MAX_LINE_CHARS: 300

        ' Keys the app can set in the manifest as a fallback when init() gets no creds.
        MANIFEST_ACCOUNT_ID: "clevertap_account_id"
        MANIFEST_TOKEN: "clevertap_token"
        MANIFEST_REGION: "clevertap_region"

        ' Manifest key for the log level. Accepted values are off, error, info and debug.
        MANIFEST_LOG_LEVEL: "clevertap_log_level"

        ' Order we look for a user identifier in onUserLogin input; first match wins.
        IDENTITY_KEYS: ["Identity", "Email", "Phone"]

        ' Profile keys the server treats as known system fields; everything else is custom.
        SYSTEM_PROFILE_KEYS: ["Name", "Email", "Phone", "Age", "Gender", "DOB", "Birthday", "Education", "Married", "Employed", "tz", "cc", "ct_optout", "ct_allow_sys_events_and_communication"]

        ' The profile key that holds the time zone. The SDK sets it from the device, once per
        ' launch. The dashboard shows it as "Timezone".
        TIMEZONE_KEY: "tz"

        ' The profile key that holds the country. The SDK sets it from the device, once per
        ' launch.
        COUNTRY_KEY: "cc"

        ' The profile key that says the viewer asked not to be reported. The SDK sets it from
        ' setOptOut. The server holds it against the profile, so a campaign built on the
        ' server is not sent to that viewer either.
        OPT_OUT_KEY: "ct_optout"

        ' The profile key that says whether the SDK's own events are still sent while opted
        ' out. See CleverTapPrivacy for what that means.
        ALLOW_SYSTEM_EVENTS_KEY: "ct_allow_sys_events_and_communication"

        ' The registry key that holds whether the app asked for network details to be
        ' reported. This is an app setting, not a viewer setting, so one key covers every
        ' viewer on the device.
        NETWORK_INFO_KEY: "netInfo"

        ' The block of extra values the server sends back and the SDK repeats in the header
        ' of every later request. See CleverTapArp.
        ARP_KEY: "arp"

        ' The name inside that block which lists the events the dashboard has switched off.
        ' It is held in memory for the run and is not saved.
        ARP_DISCARDED_EVENTS_KEY: "d_e"

        ' The value the server gives a name it is retiring. The name is then dropped rather
        ' than repeated.
        ARP_PURGE_VALUE: -1

        ' The profile key that holds a phone number. It gets a check of its own, because a
        ' phone number the server cannot dial is easy to send and hard to notice.
        PHONE_KEY: "Phone"

        ' Marks a value as a date on the wire. A date is sent as this prefix followed by the
        ' number of seconds from 1 January 1970, for example "$D_1700000000". The server
        ' reads a plain number as a number, so the prefix is what makes it a date.
        DATE_PREFIX: "$D_"

        ' The key an app writes a date under: { "DOB": { "date": "1990-04-17T00:00:00Z" } }.
        ' A date cannot be passed as an roDateTime, because an roDateTime does not survive
        ' the callfunc into the SDK node. A map does.
        DATE_MARKER_KEY: "date"

        ' How many levels deep the SDK looks for a date. A property at the top of an event is
        ' at depth 0. A property inside a map held by that property is at depth 1. A list
        ' counts as a level too, so the line items of a purchase are at depth 1 and a date
        ' written in one of them is found at depth 2.
        '
        ' The map that marks a date is not a level. It is the date itself, not something the
        ' app chose to nest, so it is read at any depth the search reaches.
        '
        ' A value deeper than this limit is copied without the parts nested inside it, and
        ' the SDK says so. The limit is what stops a value that holds itself. Such a value
        ' would otherwise be followed until the channel ran out of room to follow it.
                MAX_VALUE_DEPTH: 3

        ' Charged event keys the server gives a special meaning to. The SDK sets "Items"
        ' itself. The app supplies "Amount".
        CHARGED_RESERVED_KEYS: ["Amount", "Items"]

        ' Profile keys the server gives a special meaning to. This is SYSTEM_PROFILE_KEYS
        ' plus "Identity", which onUserLogin reads but which is not a system field.
        ' Used only to warn about a key the app spelled in the wrong letter case.
        PROFILE_RESERVED_KEYS: ["Identity", "Name", "Email", "Phone", "Age", "Gender", "DOB", "Birthday", "Education", "Married", "Employed"]

        ' Commands the server understands inside a profile update. A plain profile update
        ' replaces the value of a key. A command changes part of the value instead. The
        ' command rides in the profile object as { "key": { "$add": ... } }.
        '
        ' $set replaces the whole list of a multi-value property.
        ' $add puts values into that list.
        ' $remove takes values out of that list.
        ' $incr raises a number property by an amount.
        ' $decr lowers a number property by an amount.
        ' $delete removes the property from the profile.
        PROFILE_COMMAND_SET: "$set"
        PROFILE_COMMAND_ADD: "$add"
        PROFILE_COMMAND_REMOVE: "$remove"
        PROFILE_COMMAND_INCREMENT: "$incr"
        PROFILE_COMMAND_DECREMENT: "$decr"
        PROFILE_COMMAND_DELETE: "$delete"

        ' Most values one multi-value property may hold. Values past this limit are dropped.
        MAX_MULTI_VALUE_COUNT: 100
    }
end function

' Turns a version like "1.2.3" into the single number the server reads, here 10203.
'
' The server wants one number, not three parts. Every CleverTap SDK sends it the same way.
' The major part is multiplied by 10000. The minor part is multiplied by 100. The patch part
' is added as it is. So "7.9.0" becomes 70900, and "7.8.2" becomes 70802. Each part has to
' stay below 100, or it would run into the part above it.
'
' A missing part counts as zero, so "1.2" becomes 10200.
function CleverTapSdkRevision(version as string) as integer
    parts = version.Split(".")

    major = 0
    minor = 0
    patch = 0
    if parts.Count() > 0 then major = parts[0].ToInt()
    if parts.Count() > 1 then minor = parts[1].ToInt()
    if parts.Count() > 2 then patch = parts[2].ToInt()

    return major * 10000 + minor * 100 + patch
end function
