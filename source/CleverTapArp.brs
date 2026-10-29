' Holds the extra values the server sends back and asks the SDK to repeat.
'
' Every reply carries an "arp" block. The SDK keeps it and puts it in the header of every
' later request, so the server sees what it last told this device. The mobile SDKs do the
' same, and the server expects it.
'
' One value inside it is not kept. "d_e" lists the events the dashboard has switched off.
' That list is held in memory for the run and is left out of what is saved, because it can
' be long and it is sent again with the next reply.

' Reads the "arp" block out of a reply. Returns invalid when the reply has none.
function CleverTapExtractArp(responseBody as dynamic) as dynamic
    if responseBody = invalid or responseBody = "" then return invalid

    parsed = ParseJson(responseBody)
    if parsed = invalid then return invalid
    if GetInterface(parsed, "ifAssociativeArray") = invalid then return invalid

    arp = parsed[CleverTapConstants().ARP_KEY]
    if arp = invalid then return invalid
    if GetInterface(arp, "ifAssociativeArray") = invalid then return invalid
    return arp
end function

' Joins a new block onto the one already saved and returns what to save.
'
' A value that arrives replaces the one held under the same name. A name that has not been
' seen before is added. Nothing is ever appended to a value, so no single value grows.
'
' Two names are taken out of the result. "d_e" is held in memory instead, see above. A name
' whose value is -1 is one the server is retiring, so it is dropped rather than repeated.
function CleverTapMergeArp(stored as object, incoming as object) as object
    merged = {}
    if stored <> invalid then
        for each key in stored
            merged[key] = stored[key]
        end for
    end if

    if incoming <> invalid then
        for each key in incoming
            merged[key] = incoming[key]
        end for
    end if

    consts = CleverTapConstants()
    merged.Delete(consts.ARP_DISCARDED_EVENTS_KEY)

    for each key in merged.Keys()
        if CleverTapIsArpPurgeValue(merged[key]) then
            merged.Delete(key)
            CleverTapLogDebug("the server retired '" + key + "', so it is no longer repeated")
        end if
    end for

    return merged
end function

' True when the value is the number the server uses to retire a name.
function CleverTapIsArpPurgeValue(value as dynamic) as boolean
    if value = invalid then return false
    if GetInterface(value, "ifInt") = invalid and GetInterface(value, "ifLongInt") = invalid then return false
    return value = CleverTapConstants().ARP_PURGE_VALUE
end function

' The names of the events the dashboard has switched off, read out of an "arp" block.
' Returns an empty list when the block names none.
'
' A name may arrive as text or as a number, because an event can be named with digits alone.
' Each one is kept as text, which is how an event name is compared.
function CleverTapArpDiscardedEvents(arp as object) as object
    names = []
    if arp = invalid then return names

    listed = arp[CleverTapConstants().ARP_DISCARDED_EVENTS_KEY]
    if listed = invalid then return names
    if GetInterface(listed, "ifArray") = invalid then
        CleverTapLogDebug("the list of switched-off events could not be read, so none is applied")
        return names
    end if

    for each entry in listed
        if GetInterface(entry, "ifString") <> invalid then
            names.Push(entry)
        else if GetInterface(entry, "ifInt") <> invalid or GetInterface(entry, "ifLongInt") <> invalid then
            names.Push(entry.ToStr())
        else
            CleverTapLogDebug("one switched-off event name could not be read, so it is ignored")
        end if
    end for

    return names
end function

' True when the event name is one the dashboard has switched off. The comparison is exact,
' which is how the server lists them.
function CleverTapIsDiscardedEvent(name as string, discarded as object) as boolean
    if discarded = invalid then return false
    for each listed in discarded
        if listed = name then return true
    end for
    return false
end function
