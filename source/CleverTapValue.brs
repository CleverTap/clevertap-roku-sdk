' Turns one attribute value into the form the server expects, and reports a value that
' cannot be sent at all. Used for profile attributes, event properties and charge details.

' How an app writes a date.
'
' BrightScript has a date object, roDateTime, but an app cannot hand one to the SDK. The SDK
' is a SceneGraph node, and a call reaches it through callfunc. An roDateTime does not
' survive that call. It arrives as invalid, and the attribute would be stored as nothing.
' A map does survive, so a date is written as a map with one key:
'
'     ct.callfunc("profilePush", [{ "DOB": { "date": "1990-04-17T00:00:00Z" } }])
'     ct.callfunc("profilePush", [{ "DOB": { "date": 640310400 } }])
'
' The text form is an ISO 8601 date and time. The number form is the count of seconds from
' 1 January 1970, which is what roDateTime.AsSeconds() returns.
'
' A map is safe to use as the marker. The server stores an attribute as one value or as a
' list of values, so a map was never a value an app could send.

' True when the value is a date written the way the SDK expects.
function CleverTapIsDateMarker(value as dynamic) as boolean
    if value = invalid then return false
    if GetInterface(value, "ifAssociativeArray") = invalid then return false
    return value.DoesExist(CleverTapConstants().DATE_MARKER_KEY)
end function

' Reads the second count out of a date marker. Returns invalid when it cannot be read, and
' reports why. label names the attribute, so the report says which one is wrong.
'
' Both forms are accepted. A number is taken as a second count. Text is read as ISO 8601.
function CleverTapDateSeconds(label as string, marker as object) as dynamic
    written = marker[CleverTapConstants().DATE_MARKER_KEY]

    if written = invalid then
        CleverTapLogError("date for '" + label + "' is empty. Write it as { ""date"": ""1990-04-17T00:00:00Z"" } or as { ""date"": 640310400 }.")
        return invalid
    end if

    if GetInterface(written, "ifString") = invalid then
        if GetInterface(written, "ifInt") <> invalid or GetInterface(written, "ifLongInt") <> invalid then return written
        if GetInterface(written, "ifFloat") <> invalid or GetInterface(written, "ifDouble") <> invalid then return Int(written)

        CleverTapLogError("date for '" + label + "' must be text or a number. Write it as { ""date"": ""1990-04-17T00:00:00Z"" } or as { ""date"": 640310400 }.")
        return invalid
    end if

    trimmed = written.Trim()
    parsed = CreateObject("roDateTime")
    parsed.FromISO8601String(trimmed)
    seconds = parsed.AsSeconds()

    ' A date the device cannot read comes back as 1 January 1970 rather than as an error, so
    ' a wrong date would be stored and never questioned. The one date that really is zero
    ' seconds is let through.
    if seconds = 0 and Left(trimmed, 10) <> "1970-01-01" then
        CleverTapLogError("date for '" + label + "' could not be read from '" + written + "', so it was left out. Write the date as ""1990-04-17T00:00:00Z"", with a T between the date and the time.")
        return invalid
    end if

    return seconds
end function

' Returns the value to send for one attribute, or invalid when it cannot be sent. A caller
' leaves the attribute out when invalid comes back, so a value the server cannot store never
' replaces one it already holds.
'
' A date becomes "$D_" followed by its second count. The prefix is what marks it as a date;
' without it the server would store the number as a number. A plain number is therefore left
' alone, because the SDK cannot tell a second count apart from a score or a price.
'
' label names the attribute, for the reports.
function CleverTapEncodeValue(label as string, value as dynamic) as dynamic
    if CleverTapIsDateMarker(value) then
        seconds = CleverTapDateSeconds(label, value)
        if seconds = invalid then return invalid
        return CleverTapConstants().DATE_PREFIX + seconds.ToStr()
    end if

    if CleverTapCanSendValue(value) then return value

    if value = invalid then
        CleverTapLogError("'" + label + "' has no value, so it was left out.")
    else
        CleverTapLogError("'" + label + "' holds a " + type(value) + ", which cannot be sent, so it was left out. A date is written as { ""date"": ""1990-04-17T00:00:00Z"" }.")
    end if
    return invalid
end function

' True when the value is one the wire format can carry: text, a number, true or false, a
' list, or a map. Anything else is an object the JSON writer has no form for, and it would
' reach the server as nothing.
function CleverTapCanSendValue(value as dynamic) as boolean
    if value = invalid then return false
    if GetInterface(value, "ifString") <> invalid then return true
    if GetInterface(value, "ifBoolean") <> invalid then return true
    if GetInterface(value, "ifInt") <> invalid then return true
    if GetInterface(value, "ifFloat") <> invalid then return true
    if GetInterface(value, "ifDouble") <> invalid then return true
    if GetInterface(value, "ifLongInt") <> invalid then return true
    if GetInterface(value, "ifArray") <> invalid then return true
    if GetInterface(value, "ifAssociativeArray") <> invalid then return true
    return false
end function

' Runs every value of a map through CleverTapEncodeValue. A value that cannot be sent is left
' out of the result. The keys are not touched here; each caller checks its own keys.
function CleverTapEncodeValues(fields as object) as object
    encoded = {}
    if fields = invalid then return encoded

    for each key in fields
        value = CleverTapEncodeValue(key, fields[key])
        if value <> invalid then encoded[key] = value
    end for
    return encoded
end function
