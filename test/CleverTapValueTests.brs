' Covers the conversion every attribute value goes through: dates into the form the server
' reads, and the report for a value that cannot be sent at all.
function CleverTapValueTests(t as object)
    ' Dates are written as a map, because an roDateTime does not survive the callfunc into
    ' the SDK node. Both forms of the map are accepted.
    t.isTrue(CleverTapIsDateMarker({ "date": 640310400 }), "a map with a date key is a date")
    t.isFalse(CleverTapIsDateMarker({ "day": 1 }), "another map is not a date")
    t.isFalse(CleverTapIsDateMarker("1990-04-17T00:00:00Z"), "text on its own is not a date")
    t.isFalse(CleverTapIsDateMarker(640310400), "a number on its own is not a date")
    t.isFalse(CleverTapIsDateMarker(invalid), "invalid is not a date")

    ' A date is sent as "$D_" followed by seconds from 1 January 1970. Without the prefix
    ' the server would store the number as a number.
    t.eq(CleverTapEncodeValue("DOB", { "date": 640310400 }), "$D_640310400", "a second count becomes a prefixed date")
    t.eq(CleverTapEncodeValue("DOB", { "date": "1990-04-17T00:00:00Z" }), "$D_640310400", "an ISO 8601 date becomes the same thing")

    ' A birth date is often before 1970, which is a negative second count.
    t.eq(CleverTapEncodeValue("DOB", { "date": "1965-03-03T00:00:00Z" }), "$D_-152496000", "a date before 1970 keeps its negative count")
    t.eq(CleverTapEncodeValue("DOB", { "date": -152496000 }), "$D_-152496000", "a negative second count is accepted")

    ' 1 January 1970 is zero seconds. It has to survive, because zero is also what the
    ' device returns for a date it could not read.
    t.eq(CleverTapEncodeValue("DOB", { "date": "1970-01-01T00:00:00Z" }), "$D_0", "the epoch itself is a real date")

    ' Ordinary values are returned as they were given.
    t.eq(CleverTapEncodeValue("score", 640310400), 640310400, "a plain number stays a number")
    t.eq(CleverTapEncodeValue("Name", "Sam"), "Sam", "text stays text")
    t.eq(CleverTapEncodeValue("isPro", true), true, "true stays true")
    t.eq(CleverTapEncodeValue("tags", ["a", "b"]), ["a", "b"], "a list stays a list")

    ' --- what cannot be sent ---
    '
    ' Each of these is reported and left out. Leaving it out is the point: a value the
    ' server cannot store must not replace one it already holds. The console copy is
    ' switched off to keep the reports out of the test output.
    CleverTapLogSetConsoleOutput(false)

    ' A date the device cannot read comes back as 1 January 1970 rather than as an error, so
    ' it would otherwise be stored as a wrong date and never questioned.
    CleverTapLogClear()
    t.eq(CleverTapEncodeValue("DOB", { "date": "17 April 1990" }), invalid, "a date that cannot be read is left out")
    unreadable = CleverTapLogLines()
    t.eq(unreadable.Count(), 1, "an unreadable date is reported once")
    t.isTrue(Instr(1, unreadable[0], "DOB") > 0, "the report names the attribute")

    ' Roku's own documentation gives a form with a space in place of the T. The device does
    ' not read it, so it has to be caught rather than stored as the epoch.
    CleverTapLogClear()
    t.eq(CleverTapEncodeValue("DOB", { "date": "1990-04-17 00:00:00" }), invalid, "the form with a space instead of a T is left out")

    CleverTapLogClear()
    t.eq(CleverTapEncodeValue("DOB", { "date": invalid }), invalid, "an empty date is left out")
    t.eq(CleverTapLogLines().Count(), 1, "an empty date is reported once")

    CleverTapLogClear()
    t.eq(CleverTapEncodeValue("DOB", { "date": ["1990"] }), invalid, "a date that is neither text nor a number is left out")
    t.eq(CleverTapLogLines().Count(), 1, "that is reported once")

    CleverTapLogClear()
    t.eq(CleverTapEncodeValue("plan", invalid), invalid, "a missing value is left out")
    missing = CleverTapLogLines()
    t.eq(missing.Count(), 1, "a missing value is reported once")
    t.isTrue(Instr(1, missing[0], "plan") > 0, "the report names the attribute")

    ' An roDateTime is what an app reaches for first, and it arrives here as invalid. The
    ' report has to point at the form that does work.
    CleverTapLogClear()
    CleverTapEncodeValue("DOB", invalid)
    t.isTrue(Instr(1, CleverTapLogLines()[0], "no value") > 0, "the report says the value never arrived")

    ' --- a whole map at once ---

    CleverTapLogClear()
    encoded = CleverTapEncodeValues({ "DOB": { "date": 640310400 }, "plan": "pro", "broken": invalid })
    t.eq(encoded, { "DOB": "$D_640310400", "plan": "pro" }, "the values that can be sent survive, the one that cannot is left out")
    t.eq(CleverTapEncodeValues(invalid), {}, "no values at all is an empty map")

    CleverTapLogSetConsoleOutput(true)

    ' A date works as an event property too, not only as a profile attribute.
    sessionMeta = { s: 1700000000, pg: 1, lsl: 0, f: true }
    event = CleverTapBuildEvent("Watched", { "airedOn": { "date": 640310400 }, "title": "Bat" }, sessionMeta, 1700000000)
    t.eq(event.evtData, { "airedOn": "$D_640310400", "title": "Bat" }, "an event property can be a date")

    noProps = CleverTapBuildEvent("Watched", invalid, sessionMeta, 1700000000)
    t.eq(noProps.evtData, {}, "an event with no properties still carries an empty map")

    ' --- a date that is not at the top ---
    '
    ' An app does not always write a date at the top of an event. It puts one inside a map
    ' that describes a thing, or inside a line item of a purchase. A date found in one of
    ' those places has to become the same thing it becomes at the top. Left alone, it would
    ' reach the server as a map, and the server would store nothing a campaign can read.

    nested = CleverTapEncodeValue("show", { "airedOn": { "date": 640310400 }, "title": "Bat" })
    t.eq(nested, { "airedOn": "$D_640310400", "title": "Bat" }, "a date inside a map is converted")

    inList = CleverTapEncodeValue("dates", [{ "date": 640310400 }, { "date": -152496000 }])
    t.eq(inList, ["$D_640310400", "$D_-152496000"], "a date inside a list is converted")

    ' The line items of a purchase are a list of maps. This is the shape an app is most
    ' likely to write a date into after the top of the event.
    charged = CleverTapBuildChargedEvent({ "Amount": 300 }, [{ "id": 1, "airedOn": { "date": 640310400 } }], sessionMeta, 1700000000)
    t.eq(charged.evtData["Items"], [{ "id": 1, "airedOn": "$D_640310400" }], "a date inside a charged line item is converted")

    ' A value that cannot be read is left out wherever it sits, not only at the top. The
    ' report names the path, because "airedOn" on its own does not say which line item.
    CleverTapLogSetConsoleOutput(false)
    CleverTapLogClear()
    badItem = CleverTapBuildChargedEvent({ "Amount": 300 }, [{ "airedOn": { "date": "17 April 1990" } }], sessionMeta, 1700000000)
    t.eq(badItem.evtData["Items"], [{}], "an unreadable date is left out of its line item")
    reported = CleverTapLogLines()
    t.eq(reported.Count(), 1, "an unreadable date below the top is reported once")
    t.isTrue(Instr(1, reported[0], "Items.airedOn") > 0, "the report names the path to the value")

    ' --- how deep the search goes ---
    '
    ' Three maps of the app's own are opened. The map that marks the date is not one of
    ' them, so a date written inside the third map is still found.
    CleverTapLogClear()
    atLimit = CleverTapEncodeValue("a", { "b": { "c": { "when": { "date": 640310400 } } } })
    t.eq(atLimit, { "b": { "c": { "when": "$D_640310400" } } }, "a date three maps down is converted")
    t.eq(CleverTapLogLines().Count(), 0, "nothing is reported at the limit")

    ' One level further and the search stops. What the value holds itself is still sent.
    ' What is nested inside it is left out, because looking inside is what stopped.
    CleverTapLogClear()
    tooDeep = CleverTapEncodeValue("a", { "b": { "c": { "d": { "keep": "me", "when": { "date": 640310400 } } } } })
    t.eq(tooDeep, { "b": { "c": { "d": { "keep": "me" } } } }, "a value past the limit keeps what it holds itself")
    deepReport = CleverTapLogLines()
    t.eq(deepReport.Count(), 1, "stopping the search is reported once")
    t.isTrue(Instr(1, deepReport[0], "a.b.c.d") > 0, "the report names where the search stopped")

    ' A list counts as a level too. Without that, a list that holds itself would be followed
    ' until the channel ran out of room to follow it.
    ' The innermost list here sits at the limit. Its own text is kept and the list inside it
    ' is left out, which is the same rule a map gets.
    CleverTapLogClear()
    t.eq(CleverTapEncodeValue("a", [[[["deep", ["deeper"]]]]]), [[[["deep"]]]], "a list past the limit keeps what it holds itself")
    t.eq(CleverTapLogLines().Count(), 1, "that is reported once too")

    ' --- a value that holds itself ---
    '
    ' This is why the copy above matters, and it is the whole reason the limit exists.
    '
    ' An app can write a map that holds itself by accident. The JSON writer refuses such a
    ' value and answers with an empty string. That empty string would then be saved over the
    ' whole queue, and every event waiting on the device would be gone.
    '
    ' The SDK copies the value, so what leaves here can always be written.
    CleverTapLogClear()
    holdsItself = {}
    holdsItself["name"] = "loop"
    holdsItself["self"] = holdsItself

    t.isTrue(FormatJson(holdsItself) = "", "the writer refuses the value the app wrote")

    safe = CleverTapEncodeValue("loop", holdsItself)
    t.isTrue(FormatJson(safe) <> "", "the writer accepts the value the SDK made from it")
    t.eq(safe["name"], "loop", "the values alongside it are kept")

    ' The same for a list that holds itself.
    CleverTapLogClear()
    listHoldsItself = []
    listHoldsItself.Push("first")
    listHoldsItself.Push(listHoldsItself)
    t.isTrue(FormatJson(listHoldsItself) = "", "the writer refuses a list that holds itself")
    t.isTrue(FormatJson(CleverTapEncodeValue("loop", listHoldsItself)) <> "", "the SDK makes that list safe too")

    ' --- what must not change ---
    '
    ' Looking inside lists and maps must leave every ordinary value alone. A multi-value
    ' profile property is a list of text, and it travels through the same code.
    CleverTapLogClear()
    t.eq(CleverTapEncodeValue("favTeams", ["IND", "AUS"]), ["IND", "AUS"], "a list of text is unchanged")
    t.eq(CleverTapEncodeValue("meta", { "a": 1, "b": "two" }), { "a": 1, "b": "two" }, "a map with no date in it is unchanged")
    t.eq(CleverTapEncodeValue("counts", [1, 2, 3]), [1, 2, 3], "a list of numbers is unchanged")
    t.eq(CleverTapEncodeValue("empty", []), [], "an empty list stays empty")
    t.eq(CleverTapLogLines().Count(), 0, "none of that is reported")

    CleverTapLogSetConsoleOutput(true)
end function
