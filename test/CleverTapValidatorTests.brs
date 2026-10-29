function CleverTapValidatorTests(t as object)
    v = CleverTapValidator()

    ' A normal name passes and comes back trimmed.
    ok = v.validateEventName("  Product viewed  ")
    t.isTrue(ok.valid, "a normal event name is valid")
    t.eq(ok.value, "Product viewed", "event name is trimmed")

    ' Empty and whitespace-only names are rejected.
    t.isFalse(v.validateEventName("").valid, "empty event name is rejected")
    t.isFalse(v.validateEventName("   ").valid, "whitespace-only event name is rejected")

    ' Reserved names are rejected regardless of case.
    t.isFalse(v.validateEventName("Charged").valid, "Charged is reserved")
    t.isFalse(v.validateEventName("app launched").valid, "reserved check is case-insensitive")

    ' The reserved set draws from the mobile SDKs: fetch and bounce names.
    t.isFalse(v.validateEventName("wzrk_fetch").valid, "wzrk_fetch is reserved")
    t.isFalse(v.validateEventName("Notification Bounced").valid, "Notification Bounced is reserved")

    ' Over-long names are rejected.
    longName = "a"
    for i = 1 to 10
        longName = longName + longName
    end for
    t.isFalse(v.validateEventName(longName).valid, "over-long event name is rejected")

    ' Property keys: normal passes trimmed, empty rejected.
    pk = v.validatePropertyKey("  plan ")
    t.isTrue(pk.valid, "a normal property key is valid")
    t.eq(pk.value, "plan", "property key is trimmed")
    t.isFalse(v.validatePropertyKey("").valid, "empty property key is rejected")

    ' --- keys spelled in the wrong letter case ---
    '
    ' The device lower-cases a key written without quotes in an associative array literal,
    ' so { Amount: 300 } arrives as { amount: 300 }. The SDK cannot know what the app meant,
    ' so it only reports the key and names the spelling the server wants.

    consts = CleverTapConstants()
    t.eq(CleverTapMiscasedKey("amount", consts.CHARGED_RESERVED_KEYS), "Amount", "a lower-cased reserved key reports the spelling the server wants")
    t.eq(CleverTapMiscasedKey("AMOUNT", consts.CHARGED_RESERVED_KEYS), "Amount", "any wrong letter case is reported")
    t.eq(CleverTapMiscasedKey("Amount", consts.CHARGED_RESERVED_KEYS), invalid, "the correct spelling is not reported")
    t.eq(CleverTapMiscasedKey("discount", consts.CHARGED_RESERVED_KEYS), invalid, "a key that is not reserved is not reported")

    t.eq(CleverTapMiscasedKey("email", consts.PROFILE_RESERVED_KEYS), "Email", "a lower-cased profile key is reported")
    t.eq(CleverTapMiscasedKey("identity", consts.PROFILE_RESERVED_KEYS), "Identity", "Identity is reported even though it is not a system field")
    t.eq(CleverTapMiscasedKey("favTeam", consts.PROFILE_RESERVED_KEYS), invalid, "a custom profile key is not reported")
end function
