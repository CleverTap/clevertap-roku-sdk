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
