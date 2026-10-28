function CleverTapRequestTests(t as object)
    session = { s: 1700000000, pg: 1, lsl: 0, f: true }

    ' Upload URL carries os/version/account/timestamp as query params. "t" is the version as
    ' one number, never the dotted form, so it is built from the same constant here. A
    ' hardcoded number would have to be edited on every release.
    revision = CleverTapSdkRevision(CleverTapConstants().SDK_VERSION).ToStr()
    url = CleverTapBuildUploadUrl("in1.clevertap-prod.com", "ACC-123", 1700000000)
    t.eq(url, "https://in1.clevertap-prod.com/a1?os=Roku&t=" + revision + "&z=ACC-123&ts=1700000000", "upload url is built correctly")
    t.eq(Instr(1, url, CleverTapConstants().SDK_VERSION), 0, "the dotted version never reaches the url")

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
    charged = CleverTapBuildChargedEvent({ "Amount": 300 }, [{ "id": 1 }, { "id": 2 }], session, 1700000000)
    t.eq(charged.evtName, "Charged", "charged event uses the reserved name")
    t.eq(charged.evtData, { "Amount": 300, "Items": [{ "id": 1 }, { "id": 2 }] }, "charge details and items are merged")

    ' A charge detail spelled in the wrong letter case is reported, and still sent as given.
    ' The device turns { Amount: 300 } into { amount: 300 } before the SDK sees it, so this
    ' log line is the only way the app learns that the server will not read it as the
    ' purchase value.
    CleverTapLogSetConsoleOutput(false)
    CleverTapLogClear()
    miscased = CleverTapBuildChargedEvent({ "amount": 300 }, [], session, 1700000000)
    reported = CleverTapLogLines()
    CleverTapLogSetConsoleOutput(true)

    t.eq(reported.Count(), 1, "a charge detail in the wrong letter case is reported once")
    t.isTrue(Instr(1, reported[0], "'amount'") > 0, "the report names the key the app sent")
    t.isTrue(Instr(1, reported[0], "'Amount'") > 0, "the report names the spelling the server wants")
    t.isTrue(miscased.evtData.DoesExist("amount"), "the key is still sent exactly as the app wrote it")

    ' Batch puts the meta header first, then the items.
    batch = CleverTapBuildBatch(meta, [evt])
    t.eq(batch.Count(), 2, "batch has meta plus one event")
    t.eq(batch[0].type, "meta", "meta header comes first")
    t.eq(batch[1].evtName, "Product viewed", "event follows the header")

    ' The log description of a batch names events and marks profile updates.
    t.eq(CleverTapDescribeBatch([]), "", "an empty batch describes as an empty string")
    t.eq(CleverTapDescribeBatch([evt]), "Product viewed", "a single event is named on its own")
    t.eq(CleverTapDescribeBatch([{ type: "profile" }, evt]), "profile, Product viewed", "a profile update is named as profile")

    ' Only the first few are named. A full batch must still fit on one line.
    many = []
    for i = 1 to 8
        many.Push({ type: "event", evtName: "E" + i.ToStr() })
    end for
    t.eq(CleverTapDescribeBatch(many), "E1, E2, E3, E4, E5 and 3 more", "a long batch names the first few and counts the rest")
end function
