' Builds the exact request shape the server expects: the upload URL, the batch meta header,
' and the individual event items. Profile items are built elsewhere (CleverTapProfile) but
' ride in the same batch.
'
' A batch is a JSON array whose first element is the meta header (who and what device this
' is) followed by one element per event or profile update.

' The URL every batch is POSTed to. domain is the resolved host (region-derived, proxy, or
' handshake result); ts is the current time in unix seconds.
function CleverTapBuildUploadUrl(domain as string, accountId as string, epochSeconds as integer) as string
    consts = CleverTapConstants()
    ' "t" carries the SDK version as one number, not as "0.1.0". Every CleverTap SDK sends
    ' it that way.
    revision = CleverTapSdkRevision(consts.SDK_VERSION)
    return "https://" + domain + consts.UPLOAD_PATH + "?os=" + consts.OS_NAME + "&t=" + revision.ToStr() + "&z=" + accountId + "&ts=" + epochSeconds.ToStr()
end function

' The first element of every batch. config carries accountId + token; deviceId is the
' current GUID; appFields is the device description block.
'
' firstTs/lastTs are the first-ever and most-recent successful upload times (unix seconds,
' both 0 until the first upload lands). frs is true on the first batch of a session and false
' after. These mirror the mobile SDKs so the server sees the same new-vs-returning signals.
' arp is the block the server sent back last time, or invalid when none is held yet. It is
' repeated here so the server sees what it last told this device. An empty block is left out.
function CleverTapBuildMetaHeader(config as object, deviceId as string, appFields as object, firstTs as integer, lastTs as integer, frs as boolean, arp = invalid as dynamic) as object
    header = {
        "type": "meta"
        "af": appFields
        "g": deviceId
        "tk": config.token
        "id": config.accountId
        "ddnd": true
        "frs": frs
        "l_ts": lastTs
        "f_ts": firstTs
    }

    if arp <> invalid and arp.Count() > 0 then header[CleverTapConstants().ARP_KEY] = arp
    return header
end function

' One event item. sessionMeta supplies s/pg/lsl/f; epochSeconds is when it was recorded.
'
' Every property goes through the same conversion a profile attribute does, so a date can be
' an event property too. A property the server cannot store is left out and reported.
function CleverTapBuildEvent(name as string, props as object, sessionMeta as object, epochSeconds as integer) as object
    data = CleverTapEncodeValues(props)
    return {
        "evtName": name
        "evtData": data
        "type": "event"
        "ep": epochSeconds
        "s": sessionMeta.s
        "pg": sessionMeta.pg
        "lsl": sessionMeta.lsl
        "f": sessionMeta.f
    }
end function

' A purchase, recorded as an event named "Charged". The charge details (Amount, etc.) and
' the line items are merged into evtData under the shape the server expects.
function CleverTapBuildChargedEvent(details as object, items as object, sessionMeta as object, epochSeconds as integer) as object
    data = {}
    if details <> invalid then
        for each key in details
            CleverTapWarnMiscasedKey(key, CleverTapConstants().CHARGED_RESERVED_KEYS, "charge detail")
            data[key] = details[key]
        end for
    end if
    if items = invalid then items = []
    data["Items"] = items

    return CleverTapBuildEvent(CleverTapConstants().CHARGED_EVENT_NAME, data, sessionMeta, epochSeconds)
end function

' A short description of what a batch contains, written for the log. Events are listed by
' name. A profile update is listed as "profile". Only the first few are named. The rest are
' counted, so the line stays readable for a full batch of 49.
function CleverTapDescribeBatch(items as object) as string
    maxNamed = 5
    named = 0
    text = ""

    for each item in items
        if named >= maxNamed then exit for
        if item["type"] = "profile" then
            label = "profile"
        else
            label = item["evtName"]
        end if

        if text <> "" then text = text + ", "
        text = text + label
        named = named + 1
    end for

    remaining = items.Count() - named
    if remaining > 0 then text = text + " and " + remaining.ToStr() + " more"
    return text
end function

' Assembles the final batch array: meta header first, then the queued items.
function CleverTapBuildBatch(metaHeader as object, items as object) as object
    batch = [metaHeader]
    for each item in items
        batch.Push(item)
    end for
    return batch
end function
