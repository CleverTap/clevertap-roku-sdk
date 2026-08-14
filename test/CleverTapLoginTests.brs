function CleverTapLoginTests(t as object)
    ' Identity field is picked in priority order: Identity before Email before Phone.
    t.eq(CleverTapIdentityKeyValue({ Email: "a@x.com", Identity: "u1" }).key, "Identity", "Identity wins over Email")
    t.eq(CleverTapIdentityKeyValue({ Email: "a@x.com", Phone: "555" }).key, "Email", "Email wins over Phone")
    t.eq(CleverTapIdentityKeyValue({ Phone: 555 }).value, "555", "non-string identity value is stringified")
    t.eq(CleverTapIdentityKeyValue({ Name: "Sam" }), invalid, "no identity field returns invalid")

    ' No identifier: update the current profile, no switch.
    d0 = CleverTapResolveLogin({ Name: "Sam" }, "guid-current", true, {}, "guid-new")
    t.eq(d0.action, "profileOnly", "no identifier means profile-only")
    t.eq(d0.deviceId, "guid-current", "profile-only keeps the current id")

    ' Anonymous device: the current id is claimed for this identity, no switch.
    d1 = CleverTapResolveLogin({ Identity: "u1" }, "guid-current", false, {}, "guid-new")
    t.eq(d1.action, "claim", "anonymous device claims current id")
    t.eq(d1.deviceId, "guid-current", "claim keeps the current id")
    t.eq(d1.cacheKey, "Identity_u1", "claim records the identity key")

    ' Same user: identity already maps to the current id, no switch.
    d2 = CleverTapResolveLogin({ Identity: "u1" }, "guid-current", true, { "Identity_u1": "guid-current" }, "guid-new")
    t.eq(d2.action, "same", "identity mapping to current id is the same user")
    t.eq(d2.deviceId, "guid-current", "same user keeps the current id")

    ' Returning user: identity maps to a different known id, switch to it.
    d3 = CleverTapResolveLogin({ Identity: "u2" }, "guid-current", true, { "Identity_u2": "guid-u2" }, "guid-new")
    t.eq(d3.action, "switch", "known other identity switches user")
    t.eq(d3.deviceId, "guid-u2", "returning user reuses the cached id")
    t.isFalse(d3.isNew, "returning user is not new")

    ' New user: identity not seen before, switch to a freshly minted id.
    d4 = CleverTapResolveLogin({ Identity: "u3" }, "guid-current", true, {}, "guid-new")
    t.eq(d4.action, "switch", "unknown identity switches user")
    t.eq(d4.deviceId, "guid-new", "new user takes the fresh id")
    t.isTrue(d4.isNew, "new user is flagged new")
end function
