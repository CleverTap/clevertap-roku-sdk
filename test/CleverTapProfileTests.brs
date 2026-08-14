function CleverTapProfileTests(t as object)
    sessionMeta = { s: 1700000000, pg: 1, lsl: 0, f: true }

    ' System and custom attributes both land in one flat profile object.
    item = CleverTapBuildProfile({ Name: "Sam", plan: "pro" }, sessionMeta, 1700000000)
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

    ' An invalid custom key is dropped; the rest of the update survives.
    withBadKey = CleverTapBuildProfile({ Name: "Sam", "   ": "x", favTeam: "IND" }, sessionMeta, 1700000000)
    t.eq(withBadKey.profile, { "Name": "Sam", "favTeam": "IND" }, "blank custom key is dropped")
end function
