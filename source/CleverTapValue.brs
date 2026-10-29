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
' A map is read as a date when it holds the key "date". An app can send a map of its own as
' an event property, so one shape is given up to mark a date. The cost is small: a profile
' attribute is one value or a list of values, never a map, and a property map whose only
' meaning comes from a key named "date" is not a shape an app has reason to write.

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
' A map and a list are looked inside, so a date is found wherever it is written. The line
' items of a purchase are a list of maps, and a date in one of them is converted the same way
' a date at the top of the event is. MAX_VALUE_DEPTH says how deep the search goes.
'
' label names the attribute, for the reports. A label below the top reads as a path, such as
' "Items.airedOn", so a report names the exact place the value was written.
'
' depth is how many maps have been opened to reach this value. A caller starts at 0.
function CleverTapEncodeValue(label as string, value as dynamic, depth = 0 as integer) as dynamic
    if CleverTapIsDateMarker(value) then
        seconds = CleverTapDateSeconds(label, value)
        if seconds = invalid then return invalid
        return CleverTapConstants().DATE_PREFIX + seconds.ToStr()
    end if

    ' A list and a map are the two values that can hold other values, so they are the two
    ' that raise the depth. On Roku a list answers only to ifArray and a map only to
    ' ifAssociativeArray, so the two cannot be confused.
    if GetInterface(value, "ifArray") <> invalid then
        if depth >= CleverTapConstants().MAX_VALUE_DEPTH then return CleverTapTrimDeepValue(label, value)
        return CleverTapEncodeList(label, value, depth + 1)
    end if

    if GetInterface(value, "ifAssociativeArray") <> invalid then
        if depth >= CleverTapConstants().MAX_VALUE_DEPTH then return CleverTapTrimDeepValue(label, value)
        return CleverTapEncodeValues(value, depth + 1, label)
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
'
' depth and path are set by the encoder when it looks inside a map. A caller from outside
' leaves both alone. path is the label of the map being opened, and each key is added to it,
' so a report names the full place rather than the last key on its own.
function CleverTapEncodeValues(fields as object, depth = 0 as integer, path = "" as string) as object
    encoded = {}
    if fields = invalid then return encoded

    for each key in fields
        label = key
        if path <> "" then label = path + "." + key
        value = CleverTapEncodeValue(label, fields[key], depth)
        if value <> invalid then encoded[key] = value
    end for
    return encoded
end function

' A copy of a value that is nested too deeply to look inside. It holds only the values that
' cannot hold anything themselves: text, numbers, and true or false. A map or a list inside
' it is left out, because following that is exactly what the depth limit stopped.
'
' Making a copy is what protects the upload, and this is the only reason the limit cannot
' simply pass the value on.
'
' A map can be made to hold itself:
'
'     a = {}
'     a["self"] = a
'
' The JSON writer refuses such a value and answers with an empty string. The SDK would then
' save that empty string over a full queue, and every event waiting in it would be gone. No
' value reaches the queue by reference, so the value that leaves here is always one the JSON
' writer can write.
function CleverTapTrimDeepValue(label as string, value as dynamic) as dynamic
    consts = CleverTapConstants()
    CleverTapLogError("'" + label + "' is nested more than " + consts.MAX_VALUE_DEPTH.ToStr() + " levels deep. Its own values were sent, and anything nested inside it was left out. A date written this deep is not converted.")

    if GetInterface(value, "ifArray") <> invalid then
        keptItems = []
        for each item in value
            if CleverTapIsFlatValue(item) then keptItems.Push(item)
        end for
        return keptItems
    end if

    kept = {}
    for each key in value
        if CleverTapIsFlatValue(value[key]) then kept[key] = value[key]
    end for
    return kept
end function

' True when the value holds no other value inside it, so copying it cannot go on forever.
function CleverTapIsFlatValue(value as dynamic) as boolean
    if not CleverTapCanSendValue(value) then return false
    if GetInterface(value, "ifArray") <> invalid then return false
    if GetInterface(value, "ifAssociativeArray") <> invalid then return false
    return true
end function

' Runs every item of a list through CleverTapEncodeValue. An item that cannot be sent is left
' out, so the list that arrives at the server may be shorter than the one the app wrote.
'
' Every item carries the label of the list itself. A list has no keys, so there is no name to
' add. A report therefore names the list and not the position in it.
'
' The caller has already raised the depth for the list itself, so every item is read at the
' depth of the list.
function CleverTapEncodeList(label as string, items as object, depth as integer) as object
    encoded = []
    if items = invalid then return encoded

    for each item in items
        value = CleverTapEncodeValue(label, item, depth)
        if value <> invalid then encoded.Push(value)
    end for
    return encoded
end function
