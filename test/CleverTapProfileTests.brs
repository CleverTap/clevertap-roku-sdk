function CleverTapProfileTests(t as object)
    sessionMeta = { s: 1700000000, pg: 1, lsl: 0, f: true }

    ' System and custom attributes both land in one flat profile object.
    item = CleverTapBuildProfile({ "Name": "Sam", "plan": "pro" }, sessionMeta, 1700000000)
    expected = {
        "type": "profile"
        "profile": { "Name": "Sam", "plan": "pro" }
        "ep": 1700000000
        "s": 1700000000
        "pg": 1
        "lsl": 0
        "f": true
    }
    t.eq(item, expected, "profile item matches expected shape")

    ' Known system keys are recognised (case-sensitive to match the server).
    t.isTrue(CleverTapIsSystemProfileKey("Email"), "Email is a system key")
    t.isFalse(CleverTapIsSystemProfileKey("favTeam"), "favTeam is a custom key")

    ' The same conversion happens on a system key and on a custom key.
    dated = CleverTapBuildProfile({ "DOB": { "date": 640656000 }, "joined": { "date": 640656000 }, "Name": "Sam" }, sessionMeta, 1700000000)
    t.eq(dated.profile["DOB"], "$D_640656000", "DOB is sent as a date")
    t.eq(dated.profile["joined"], "$D_640656000", "a custom date key is sent as a date")
    t.eq(dated.profile["Name"], "Sam", "other values are untouched")

    ' An invalid custom key is dropped; the rest of the update survives. The SDK logs an
    ' error when it drops one, so the console copy is switched off to keep that line out of
    ' the test output. The line itself is checked below.
    CleverTapLogSetConsoleOutput(false)
    CleverTapLogClear()
    withBadKey = CleverTapBuildProfile({ "Name": "Sam", "   ": "x", "favTeam": "IND" }, sessionMeta, 1700000000)
    dropped = CleverTapLogLines()
    CleverTapLogSetConsoleOutput(true)

    t.eq(withBadKey.profile, { "Name": "Sam", "favTeam": "IND" }, "blank custom key is dropped")
    t.eq(dropped.Count(), 1, "dropping a key is reported once")
    t.isTrue(Instr(1, dropped[0], "Property key is empty") > 0, "the report says why the key was dropped")

    CleverTapPhoneTests(t)
    CleverTapProfileCommandTests(t)
end function

' Covers the phone number check. It only writes to the log. The number is always sent.
function CleverTapPhoneTests(t as object)
    sessionMeta = { s: 1700000000, pg: 1, lsl: 0, f: true }

    ' Every case below is driven through CleverTapBuildProfile, because the point of the
    ' check is what reaches the wire. The console copy is switched off so the reports stay
    ' out of the test output.
    CleverTapLogSetConsoleOutput(false)

    ' The device knows its country, so a number without a "+" is fine. The server completes
    ' it from the country of the device.
    CleverTapLogClear()
    known = CleverTapBuildProfile({ "Phone": "4155550123" }, sessionMeta, 1700000000, "US")
    t.eq(CleverTapLogLines().Count(), 0, "a bare number is not reported when the device knows its country")
    t.eq(known.profile["Phone"], "4155550123", "the number is sent as given")

    ' The device reports no country. The number carries its own, so there is nothing to
    ' report.
    CleverTapLogClear()
    withPlus = CleverTapBuildProfile({ "Phone": "+14155550123" }, sessionMeta, 1700000000, "")
    t.eq(CleverTapLogLines().Count(), 0, "a number with a country code is not reported")
    t.eq(withPlus.profile["Phone"], "+14155550123", "the leading plus is kept")

    ' Spaces around the number do not hide the "+".
    CleverTapLogClear()
    CleverTapBuildProfile({ "Phone": "  +14155550123  " }, sessionMeta, 1700000000, "")
    t.eq(CleverTapLogLines().Count(), 0, "spaces around the number do not hide the country code")

    ' Neither side carries a country. This is the case the check exists for.
    CleverTapLogClear()
    noCountry = CleverTapBuildProfile({ "Phone": "4155550123" }, sessionMeta, 1700000000, "")
    reported = CleverTapLogLines()
    t.eq(reported.Count(), 1, "a bare number on a device with no country is reported once")
    t.isTrue(Instr(1, reported[0], "+14155550123") > 0, "the report shows how to write the number")
    t.eq(noCountry.profile["Phone"], "4155550123", "the number is still sent after a report")

    ' A number written without quotes is reported whatever the device knows, because it has
    ' already lost a leading "+" by the time the SDK sees it.
    CleverTapLogClear()
    asNumber = CleverTapBuildProfile({ "Phone": 5550123 }, sessionMeta, 1700000000, "US")
    numberReported = CleverTapLogLines()
    t.eq(numberReported.Count(), 1, "a phone number that is not text is reported")
    t.isTrue(Instr(1, numberReported[0], "must be text") > 0, "the report says the number has to be text")
    t.eq(asNumber.profile["Phone"], 5550123, "the value is still sent as given")

    ' "phone" in the wrong letter case still gets the check. It is reported twice: once for
    ' the spelling, once for the number.
    CleverTapLogClear()
    miscased = CleverTapBuildProfile({ "phone": "4155550123" }, sessionMeta, 1700000000, "")
    t.eq(CleverTapLogLines().Count(), 2, "a miscased phone key is reported for its spelling and for its number")
    t.eq(miscased.profile["phone"], "4155550123", "the miscased key is still sent")

    ' No other key is checked, even one whose value looks like a phone number.
    CleverTapLogClear()
    CleverTapBuildProfile({ "altNumber": "4155550123" }, sessionMeta, 1700000000, "")
    t.eq(CleverTapLogLines().Count(), 0, "only the phone key is checked")

    CleverTapLogSetConsoleOutput(true)
end function

' Covers the profile commands: the item each one builds, and the checks that stop a bad one
' from being queued.
function CleverTapProfileCommandTests(t as object)
    sessionMeta = { s: 1700000000, pg: 1, lsl: 0, f: true }
    consts = CleverTapConstants()

    ' A command rides in the same item shape a plain profile update uses. Only the profile
    ' object differs: the value of the key is the command, not a new value.
    item = CleverTapBuildProfileCommand("favTeams", consts.PROFILE_COMMAND_ADD, ["IND"], sessionMeta, 1700000000)
    expected = {
        "type": "profile"
        "profile": { "favTeams": { "$add": ["IND"] } }
        "ep": 1700000000
        "s": 1700000000
        "pg": 1
        "lsl": 0
        "f": true
    }
    t.eq(item, expected, "a command item matches the plain profile item shape")

    ' The six command names are the ones the server reads.
    t.eq(consts.PROFILE_COMMAND_SET, "$set", "set command name")
    t.eq(consts.PROFILE_COMMAND_ADD, "$add", "add command name")
    t.eq(consts.PROFILE_COMMAND_REMOVE, "$remove", "remove command name")
    t.eq(consts.PROFILE_COMMAND_INCREMENT, "$incr", "increment command name")
    t.eq(consts.PROFILE_COMMAND_DECREMENT, "$decr", "decrement command name")
    t.eq(consts.PROFILE_COMMAND_DELETE, "$delete", "delete command name")

    ' Removing a property sends true, not a value.
    removal = CleverTapBuildProfileCommand("plan", consts.PROFILE_COMMAND_DELETE, true, sessionMeta, 1700000000)
    t.eq(removal.profile, { "plan": { "$delete": true } }, "a removal sends true")

    ' An amount rides as a bare number, not as a list.
    bump = CleverTapBuildProfileCommand("points", consts.PROFILE_COMMAND_INCREMENT, 5, sessionMeta, 1700000000)
    t.eq(bump.profile, { "points": { "$incr": 5 } }, "an amount is sent as a bare number")

    ' --- multi-value checks ---

    ok = CleverTapNormaliseMultiValues(["IND", "AUS"])
    t.isTrue(ok.valid, "a list of strings is accepted")
    t.eq(ok.value, ["IND", "AUS"], "the strings are kept as given")

    ' A multi-value property holds strings, so a number is turned into one.
    numbers = CleverTapNormaliseMultiValues([1, 2])
    t.eq(numbers.value, ["1", "2"], "numbers become strings")

    t.isFalse(CleverTapNormaliseMultiValues([]).valid, "an empty list is rejected")
    t.isFalse(CleverTapNormaliseMultiValues(invalid).valid, "a missing list is rejected")
    t.isFalse(CleverTapNormaliseMultiValues("IND").valid, "a single string is not a list")

    ' A value that cannot become a string is dropped. The rest of the list survives. The SDK
    ' logs that drop, so the console copy is switched off to keep the line out of the test
    ' output.
    CleverTapLogSetConsoleOutput(false)
    CleverTapLogClear()
    mixed = CleverTapNormaliseMultiValues(["IND", { "a": 1 }, "AUS"])
    mixedLines = CleverTapLogLines()
    CleverTapLogSetConsoleOutput(true)

    t.isTrue(mixed.valid, "the list survives one bad value")
    t.eq(mixed.value, ["IND", "AUS"], "a nested object is dropped from the list")
    t.eq(mixedLines.Count(), 1, "dropping a value is reported once")

    ' The list is cut to MAX_MULTI_VALUE_COUNT.
    long = []
    for i = 1 to consts.MAX_MULTI_VALUE_COUNT + 10
        long.Push("v" + i.ToStr())
    end for
    CleverTapLogSetConsoleOutput(false)
    CleverTapLogClear()
    capped = CleverTapNormaliseMultiValues(long)
    CleverTapLogSetConsoleOutput(true)

    t.eq(capped.value.Count(), consts.MAX_MULTI_VALUE_COUNT, "a long list is cut to the limit")
    t.eq(capped.value[0], "v1", "the list is cut from the end, not the start")

    ' --- amount checks ---

    t.isTrue(CleverTapValidateCommandAmount(5).valid, "a whole number is an amount")
    t.isTrue(CleverTapValidateCommandAmount(2.5).valid, "a fraction is an amount")
    t.isFalse(CleverTapValidateCommandAmount(0).valid, "zero is not an amount")
    t.isFalse(CleverTapValidateCommandAmount(-1).valid, "a negative number is not an amount")
    t.isFalse(CleverTapValidateCommandAmount("5").valid, "text is not an amount")
    t.isFalse(CleverTapValidateCommandAmount(invalid).valid, "a missing amount is rejected")

    ' --- key checks ---

    t.isTrue(CleverTapValidateCommandKey("favTeams").valid, "a plain key is accepted")
    t.eq(CleverTapValidateCommandKey("  favTeams  ").value, "favTeams", "spaces around a key are trimmed")

    CleverTapLogSetConsoleOutput(false)
    CleverTapLogClear()
    blank = CleverTapValidateCommandKey("   ")
    CleverTapLogSetConsoleOutput(true)
    t.isFalse(blank.valid, "a blank key is rejected")

    ' A key spelled in the wrong letter case is reported but still accepted, because only the
    ' app knows what it meant.
    CleverTapLogSetConsoleOutput(false)
    CleverTapLogClear()
    miscased = CleverTapValidateCommandKey("email")
    miscasedLines = CleverTapLogLines()
    CleverTapLogSetConsoleOutput(true)

    t.isTrue(miscased.valid, "a key in the wrong letter case is still accepted")
    t.eq(miscasedLines.Count(), 1, "the wrong letter case is reported once")
    t.isTrue(Instr(1, miscasedLines[0], "Email") > 0, "the report names the spelling the server wants")

    ' --- what the log says ---
    '
    ' The command names are wire tokens, so the log describes the change in plain words
    ' instead of printing "$add".

    t.eq(CleverTapDescribeProfileCommand(consts.PROFILE_COMMAND_DELETE, "plan", true), "plan removed from the profile", "a removal reads plainly")
    t.eq(CleverTapDescribeProfileCommand(consts.PROFILE_COMMAND_INCREMENT, "points", 50), "points raised by 50", "an increment reads plainly")
    t.eq(CleverTapDescribeProfileCommand(consts.PROFILE_COMMAND_DECREMENT, "points", 20), "points lowered by 20", "a decrement reads plainly")
    t.eq(CleverTapDescribeProfileCommand(consts.PROFILE_COMMAND_SET, "favTeams", ["IND", "AUS"]), "favTeams set to 2 values", "a set reads plainly")
    t.eq(CleverTapDescribeProfileCommand(consts.PROFILE_COMMAND_ADD, "favTeams", ["ENG"]), "1 value added to favTeams", "one added value is not called values")
    t.eq(CleverTapDescribeProfileCommand(consts.PROFILE_COMMAND_REMOVE, "favTeams", ["NZ", "SA"]), "2 values removed from favTeams", "a removal of several reads plainly")

    ' No description leaks a command name into the log.
    for each command in [consts.PROFILE_COMMAND_SET, consts.PROFILE_COMMAND_ADD, consts.PROFILE_COMMAND_REMOVE]
        t.isTrue(Instr(1, CleverTapDescribeProfileCommand(command, "favTeams", ["IND"]), "$") = 0, "no wire token in the line for " + command)
    end for
end function
