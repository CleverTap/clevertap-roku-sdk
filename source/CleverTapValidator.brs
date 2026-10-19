' Lightweight checks for event names and property keys before they are queued. The goal is
' to catch obviously bad input (empty, too long, or a name the server reserves for its own
' use) and tell the caller what went wrong so it can log and skip that item.
'
' Each check returns { valid, value, message }: value is the trimmed input to use when
' valid, and message explains the problem when not.

' Event names the server generates itself; apps must not send these through recordEvent.
' Draws from the reserved set the mobile SDKs block, minus the push/geofence names Roku has
' no features for. "Charged" is reserved for recordChargedEvent; "Notification Bounced" is a
' Roku extra the server also owns.
function CleverTapRestrictedEventNames() as object
    return [
        "Notification Clicked", "Notification Viewed", "Notification Sent",
        "Notification Bounced", "UTM Visited", "App Launched", "App Uninstalled",
        "Stayed", "wzrk_fetch", "wzrk_d", "Charged"
    ]
end function

' Finds a key the app spelled with the wrong letters in upper or lower case.
'
' The server matches reserved key names exactly. "Amount" is the purchase value. "amount" is
' an ordinary custom property, and the server does not report it as revenue. BrightScript
' makes this easy to get wrong: a key written without quotes inside an associative array
' literal is an identifier, and the device stores every identifier in lower case. So
' { Amount: 300 } reaches the SDK as { amount: 300 }, and the original spelling is already
' gone. Writing the key in quotes, as { "Amount": 300 }, keeps it.
'
' knownKeys holds the spellings the server expects. Returns the expected spelling when key
' matches one of them apart from letter case. Returns invalid when key matches exactly, and
' when it is not a reserved key at all.
function CleverTapMiscasedKey(key as string, knownKeys as object) as dynamic
    lower = LCase(key)
    for each known in knownKeys
        if known = key then return invalid
        if LCase(known) = lower then return known
    end for
    return invalid
end function

' Logs a key the app spelled with the wrong letter case, and names the fix. The key is sent
' on as given, because only the app knows what it meant. label says where the key came from,
' for example "charge detail" or "profile field".
sub CleverTapWarnMiscasedKey(key as string, knownKeys as object, label as string)
    expected = CleverTapMiscasedKey(key, knownKeys)
    if expected = invalid then return
    CleverTapLogError(label + " '" + key + "' is sent as a custom property. The server reads it as '" + expected + "' only when it is spelled that way. Write the key in quotes: { """ + expected + """: ... }")
end sub

' Longest values the server accepts.
function CleverTapValidator() as object
    return {
        maxEventNameLength: 512
        maxPropertyKeyLength: 120

        validateEventName: function(name as dynamic) as object
            if name = invalid or GetInterface(name, "ifString") = invalid then
                return { valid: false, value: "", message: "Event name must be a string" }
            end if

            trimmed = name.Trim()
            if trimmed = "" then
                return { valid: false, value: "", message: "Event name is empty" }
            end if
            if Len(trimmed) > m.maxEventNameLength then
                return { valid: false, value: trimmed, message: "Event name exceeds " + m.maxEventNameLength.ToStr() + " characters" }
            end if

            lower = LCase(trimmed)
            for each reserved in CleverTapRestrictedEventNames()
                if LCase(reserved) = lower then
                    return { valid: false, value: trimmed, message: "'" + trimmed + "' is a restricted event name" }
                end if
            end for

            return { valid: true, value: trimmed, message: "" }
        end function

        validatePropertyKey: function(key as dynamic) as object
            if key = invalid or GetInterface(key, "ifString") = invalid then
                return { valid: false, value: "", message: "Property key must be a string" }
            end if

            trimmed = key.Trim()
            if trimmed = "" then
                return { valid: false, value: "", message: "Property key is empty" }
            end if
            if Len(trimmed) > m.maxPropertyKeyLength then
                return { valid: false, value: trimmed, message: "Property key exceeds " + m.maxPropertyKeyLength.ToStr() + " characters" }
            end if

            return { valid: true, value: trimmed, message: "" }
        end function
    }
end function
