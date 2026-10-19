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
end function
