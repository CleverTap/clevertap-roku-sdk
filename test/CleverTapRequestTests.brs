function CleverTapRequestTests(t as object)
    session = { s: 1700000000, pg: 1, lsl: 0, f: true }

    ' Upload URL carries os/version/account/timestamp as query params.
    url = CleverTapBuildUploadUrl("in1.clevertap-prod.com", "ACC-123", 1700000000)
    t.eq(url, "https://in1.clevertap-prod.com/a1?os=Roku&t=0.1.0&z=ACC-123&ts=1700000000", "upload url is built correctly")

    ' Meta header matches the expected shape exactly. Timestamps and frs are passed through.
    af = { "Make": "Roku", "OS": "Roku" }
    meta = CleverTapBuildMetaHeader({ accountId: "ACC-123", token: "TOK-9" }, "guid-1", af, 1699990000, 1700000000, false)
    expectedMeta = {
        "type": "meta"
        "af": { "Make": "Roku", "OS": "Roku" }
        "g": "guid-1"
        "tk": "TOK-9"
        "id": "ACC-123"
        "ddnd": true
        "frs": false
        "l_ts": 1700000000
        "f_ts": 1699990000
    }
    t.eq(meta, expectedMeta, "meta header matches golden shape")

    ' Event item matches the expected shape, and missing props become an empty object.
    evt = CleverTapBuildEvent("Product viewed", { id: 42 }, session, 1700000000)
    expectedEvt = {
        "evtName": "Product viewed"
        "evtData": { id: 42 }
        "type": "event"
        "ep": 1700000000
        "s": 1700000000
        "pg": 1
        "lsl": 0
        "f": true
    }
    t.eq(evt, expectedEvt, "event item matches golden shape")

    evtNoProps = CleverTapBuildEvent("Opened", invalid, session, 1700000000)
    t.eq(evtNoProps.evtData, {}, "missing props default to an empty object")

    ' Charged event uses the reserved name and folds Items into evtData.
    charged = CleverTapBuildChargedEvent({ Amount: 300 }, [{ id: 1 }, { id: 2 }], session, 1700000000)
    t.eq(charged.evtName, "Charged", "charged event uses the reserved name")
    t.eq(charged.evtData, { Amount: 300, Items: [{ id: 1 }, { id: 2 }] }, "charge details and items are merged")

    ' Batch puts the meta header first, then the items.
    batch = CleverTapBuildBatch(meta, [evt])
    t.eq(batch.Count(), 2, "batch has meta plus one event")
    t.eq(batch[0].type, "meta", "meta header comes first")
    t.eq(batch[1].evtName, "Product viewed", "event follows the header")
end function
