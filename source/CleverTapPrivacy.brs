' Holds the opt-out choice a viewer made, and decides what may still be sent.
'
' A viewer has the right to stop an app from reporting what they do. The app offers that
' choice in its own settings screen. The app then tells the SDK by calling setOptOut.
'
' There are three states.
'
'   Opted in. Everything is sent. This is the state of a new install.
'   Opted out, system events allowed. Events the app records are dropped. Events the SDK
'     records for its own bookkeeping are still sent. Profile changes are still sent.
'   Opted out fully. Nothing is sent at all.
'
' The middle state exists because some events are not about the viewer. "App Launched" says
' a channel opened. The server needs it to close off a session. Dropping it leaves sessions
' that never end.
'
' The choice is kept on the device. It is read back the next time the channel opens. A
' viewer does not have to opt out again on every launch.

' The state of a viewer who has not chosen anything.
'
' The SDK sends data until it is told not to. This matches the mobile SDKs. An app that wants
' the opposite calls setOptOut(true) before it records anything.
function CleverTapPrivacyDefault() as object
    return { optedOut: false, allowSystemEvents: true }
end function

' Works out the state for a call to setOptOut.
'
' allowSystemEvents is only meaningful while opted out. A viewer who is opted in is sent
' everything, so the flag is forced to true there. This mirrors the mobile SDKs: calling
' setOptOut(true) with no second argument means a full opt-out.
function CleverTapPrivacyResolve(optedOut as boolean, allowSystemEvents as boolean) as object
    resolved = allowSystemEvents
    if not optedOut then resolved = true
    return { optedOut: optedOut, allowSystemEvents: resolved }
end function

' The profile attributes that tell the server about the choice.
'
' The server holds the same choice against the profile. A campaign is then not sent to a
' viewer who opted out, even though the campaign is built on the server.
'
' The key names are the ones the mobile SDKs use. The server reads those exact names.
function CleverTapPrivacyProfileFields(state as object) as object
    consts = CleverTapConstants()
    fields = {}
    fields[consts.OPT_OUT_KEY] = state.optedOut
    fields[consts.ALLOW_SYSTEM_EVENTS_KEY] = state.allowSystemEvents
    return fields
end function

' Decides whether one item may be sent.
'
' kind is "event" for anything the app records. kind is "profile" for an attribute change.
' name is the event name. name is ignored for a profile.
'
' A profile change survives a partial opt-out on purpose. The opt-out itself is sent as a
' profile change. Dropping profile changes would drop the message that reports the opt-out.
function CleverTapPrivacyAllows(kind as string, name as string, state as object) as boolean
    if not state.optedOut then return true
    if not state.allowSystemEvents then return false
    if kind <> "event" then return true

    ' Only the SDK's own events are still sent. An event the app recorded is about the
    ' viewer, so it is dropped.
    return CleverTapPrivacyIsSystemEvent(name)
end function

' Tells whether the SDK records this event for itself.
'
' This is a different question from the one the validator asks, so it has its own list. The
' validator lists names an app may not record. This lists names that are not about the
' viewer. Most names are on both lists. Two are not.
'
' "Charged" is on the validator's list and not on this one. An app may not pass that name to
' recordEvent, because recordChargedEvent owns it. A purchase is still something the viewer
' did. A viewer who opted out does not expect their purchases to be reported.
'
' "Notification Bounced" is on the validator's list and not on this one for the same reason
' the others are not: the SDK never records it. Only the server does. Keeping it here would
' not change any behaviour. Leaving it out keeps this list to the names that can really
' reach the check.
function CleverTapPrivacySystemEventNames() as object
    return ["App Launched", "Stayed", "Notification Clicked", "Notification Viewed", "Notification Sent", "App Uninstalled", "UTM Visited", "wzrk_fetch", "wzrk_d"]
end function

function CleverTapPrivacyIsSystemEvent(name as string) as boolean
    for each systemName in CleverTapPrivacySystemEventNames()
        if systemName = name then return true
    end for
    return false
end function

' --- keeping the choice on the device ---

' The registry key the choice is kept under.
'
' The key carries the device id. Two viewers on one TV each keep their own choice. A viewer
' who opted out, signed out, then signed back in is still opted out.
'
' This costs one small entry per viewer who signs in. The SDK keeps a single entry for the
' server block instead of one per viewer, because that block can be fetched again. An
' opt-out cannot be fetched again. Losing it would start reporting a viewer who asked not to
' be reported, so the extra entries are worth their space.
function CleverTapPrivacyStorageKey(deviceId as string) as string
    return "optOut:" + deviceId
end function

' Turns the state into the two characters kept in the registry.
'
' A Roku app gets 32K of registry in total. The SDK shares it with the channel. Two
' characters are used rather than a readable form, because every byte here is a byte the
' channel cannot use.
'
' The first character is the opt-out. The second is whether system events are still allowed.
' "1" means true. "0" means false.
function CleverTapPrivacyEncode(state as object) as string
    return CleverTapPrivacyFlagChar(state.optedOut) + CleverTapPrivacyFlagChar(state.allowSystemEvents)
end function

function CleverTapPrivacyFlagChar(flag as boolean) as string
    if flag then return "1"
    return "0"
end function

' Reads back what was kept. Gives the default state when nothing was kept.
'
' Anything that is not exactly two characters is treated as nothing. A half-written entry
' then reads as opted in. That is the same state a new install starts in.
function CleverTapPrivacyDecode(raw as dynamic) as object
    if raw = invalid then return CleverTapPrivacyDefault()
    if GetInterface(raw, "ifString") = invalid then return CleverTapPrivacyDefault()
    if Len(raw) <> 2 then return CleverTapPrivacyDefault()

    ' An opted-in viewer is always allowed system events. Reading the second character on its
    ' own could give a pair that setOptOut can never produce.
    return CleverTapPrivacyResolve(Mid(raw, 1, 1) = "1", Mid(raw, 2, 1) = "1")
end function

' Says in plain words what the state means. Used by the log.
function CleverTapPrivacyDescribe(state as object) as string
    if not state.optedOut then return "opted in, everything is sent"
    if state.allowSystemEvents then return "opted out, only the SDK's own events are still sent"
    return "opted out fully, nothing is sent"
end function
