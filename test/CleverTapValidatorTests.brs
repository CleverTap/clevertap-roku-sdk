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
end function
