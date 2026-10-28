' Covers the block the server sends back and the SDK repeats: reading it out of a reply,
' joining it onto the one already held, and the list of events the dashboard switched off.
function CleverTapArpTests(t as object)
    ' --- reading it out of a reply ---

    body = "{""arp"":{""id"":""W8R-ZR9-Z96Z"",""dh"":0,""v"":2},""g"":""guid-1""}"
    t.eq(CleverTapExtractArp(body), { "id": "W8R-ZR9-Z96Z", "dh": 0, "v": 2 }, "the block is read out of a reply")

    t.eq(CleverTapExtractArp("{""g"":""guid-1""}"), invalid, "a reply without the block gives nothing")
    t.eq(CleverTapExtractArp("not json"), invalid, "a reply that is not JSON gives nothing")
    t.eq(CleverTapExtractArp(""), invalid, "an empty reply gives nothing")
    t.eq(CleverTapExtractArp(invalid), invalid, "no reply at all gives nothing")
    t.eq(CleverTapExtractArp("{""arp"":""text""}"), invalid, "a block that is not a map gives nothing")

    ' --- joining a new block onto the one held ---

    ' A value that arrives replaces the one held under the same name, and a name that is new
    ' is added. Nothing is appended, so no single value grows.
    joined = CleverTapMergeArp({ "id": "acct-1", "dh": 0 }, { "dh": 7, "r_ts": 1700000000 })
    t.eq(joined, { "id": "acct-1", "dh": 7, "r_ts": 1700000000 }, "a value is replaced and a new name is added")

    t.eq(CleverTapMergeArp(invalid, { "v": 2 }), { "v": 2 }, "the first block is held as it is")
    t.eq(CleverTapMergeArp({ "v": 2 }, invalid), { "v": 2 }, "a reply with no block leaves the held one alone")

    ' The list of switched-off events is held in memory for the run, so it is never saved.
    ' It can be long, and the server sends it again with the next reply.
    withList = CleverTapMergeArp({}, { "v": 2, "d_e": ["Product viewed"] })
    t.isFalse(withList.DoesExist("d_e"), "the list of switched-off events is not saved")
    t.eq(withList, { "v": 2 }, "everything else is saved")

    ' -1 is how the server retires a name. It is dropped rather than repeated, otherwise the
    ' SDK would send it back forever.
    CleverTapLogSetConsoleOutput(false)
    retired = CleverTapMergeArp({ "old": 5, "keep": 1 }, { "old": -1 })
    CleverTapLogSetConsoleOutput(true)
    t.isFalse(retired.DoesExist("old"), "a name the server retires is dropped")
    t.eq(retired, { "keep": 1 }, "the other names are left alone")

    ' -1 only retires a name when it really is the number. Text that reads the same is a
    ' value in its own right.
    t.eq(CleverTapIsArpPurgeValue(-1), true, "the number -1 retires a name")
    t.eq(CleverTapIsArpPurgeValue("-1"), false, "the text -1 does not")
    t.eq(CleverTapIsArpPurgeValue(0), false, "zero does not")
    t.eq(CleverTapIsArpPurgeValue(invalid), false, "no value does not")

    ' --- the events the dashboard switched off ---

    t.eq(CleverTapArpDiscardedEvents({ "d_e": ["Product viewed", "Watched"] }), ["Product viewed", "Watched"], "the names are read out")
    t.eq(CleverTapArpDiscardedEvents({ "v": 2 }), [], "a block that lists none gives an empty list")
    t.eq(CleverTapArpDiscardedEvents(invalid), [], "no block gives an empty list")

    ' An event can be named with digits alone, and such a name arrives as a number. It is
    ' kept as text, which is how an event name is compared.
    t.eq(CleverTapArpDiscardedEvents({ "d_e": [42] }), ["42"], "a name made of digits is kept as text")

    CleverTapLogSetConsoleOutput(false)
    t.eq(CleverTapArpDiscardedEvents({ "d_e": "Product viewed" }), [], "a list that is not a list is ignored")
    t.eq(CleverTapArpDiscardedEvents({ "d_e": [{ "name": "x" }] }), [], "a name that cannot be read is left out")
    CleverTapLogSetConsoleOutput(true)

    ' --- matching an event against the list ---

    switchedOff = ["Product viewed", "Watched"]
    t.isTrue(CleverTapIsDiscardedEvent("Product viewed", switchedOff), "a switched-off event is matched")
    t.isFalse(CleverTapIsDiscardedEvent("Added to cart", switchedOff), "another event is not")
    t.isFalse(CleverTapIsDiscardedEvent("product viewed", switchedOff), "the match is exact, so another letter case is not switched off")
    t.isFalse(CleverTapIsDiscardedEvent("Product viewed", []), "nothing is switched off when the list is empty")
    t.isFalse(CleverTapIsDiscardedEvent("Product viewed", invalid), "nothing is switched off before a reply arrives")

    ' --- repeating it in the header ---

    config = { accountId: "acct-1", token: "token-1" }
    held = { "id": "acct-1", "dh": 7 }
    header = CleverTapBuildMetaHeader(config, "guid-1", {}, 0, 0, true, held)
    t.eq(header["arp"], held, "the held block is repeated in the header")

    ' Before the first reply there is nothing to repeat, and an empty block is left out
    ' rather than sent as an empty map.
    t.isFalse(CleverTapBuildMetaHeader(config, "guid-1", {}, 0, 0, true, {}).DoesExist("arp"), "an empty block is left out of the header")
    t.isFalse(CleverTapBuildMetaHeader(config, "guid-1", {}, 0, 0, true).DoesExist("arp"), "a header built without a block has none")
end function
