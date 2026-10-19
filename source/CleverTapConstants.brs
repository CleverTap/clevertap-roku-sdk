' Central place for the fixed values the SDK needs: server domains, endpoints, header
' names, batch limits, and the registry/manifest keys we read and write. Kept in one
' function so callers grab a single map instead of scattering magic strings around.
function CleverTapConstants() as object
    return {
        ' SDK version reported to the server (the "t" query param on uploads).
        SDK_VERSION: "0.1.0"

        ' Reported as the "os" query param and inside the app-fields block.
        OS_NAME: "Roku"

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
        SYSTEM_PROFILE_KEYS: ["Name", "Email", "Phone", "Age", "Gender", "DOB", "Birthday", "Education", "Married", "Employed"]

        ' Charged event keys the server gives a special meaning to. The SDK sets "Items"
        ' itself. The app supplies "Amount".
        CHARGED_RESERVED_KEYS: ["Amount", "Items"]

        ' Profile keys the server gives a special meaning to. This is SYSTEM_PROFILE_KEYS
        ' plus "Identity", which onUserLogin reads but which is not a system field.
        ' Used only to warn about a key the app spelled in the wrong letter case.
        PROFILE_RESERVED_KEYS: ["Identity", "Name", "Email", "Phone", "Age", "Gender", "DOB", "Birthday", "Education", "Married", "Employed"]
    }
end function
