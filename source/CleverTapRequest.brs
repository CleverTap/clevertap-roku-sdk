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
    return "https://" + domain + consts.UPLOAD_PATH + "?os=" + consts.OS_NAME + "&t=" + consts.SDK_VERSION + "&z=" + accountId + "&ts=" + epochSeconds.ToStr()
end function

' The first element of every batch. config carries accountId + token; deviceId is the
' current GUID; appFields is the device description block.
function CleverTapBuildMetaHeader(config as object, deviceId as string, appFields as object) as object
    return {
        "type": "meta"
        "af": appFields
        "g": deviceId
        "tk": config.token
        "id": config.accountId
        "ddnd": true
        "frs": true
        "l_ts": 0
        "f_ts": 0
    }
end function

' One event item. sessionMeta supplies s/pg/lsl/f; epochSeconds is when it was recorded.
function CleverTapBuildEvent(name as string, props as object, sessionMeta as object, epochSeconds as integer) as object
    data = props
    if data = invalid then data = {}
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
            data[key] = details[key]
        end for
    end if
    if items = invalid then items = []
    data["Items"] = items

    return CleverTapBuildEvent(CleverTapConstants().CHARGED_EVENT_NAME, data, sessionMeta, epochSeconds)
end function

' Assembles the final batch array: meta header first, then the queued items.
function CleverTapBuildBatch(metaHeader as object, items as object) as object
    batch = [metaHeader]
    for each item in items
        batch.Push(item)
    end for
    return batch
end function
