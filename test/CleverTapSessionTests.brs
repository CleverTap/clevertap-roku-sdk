function CleverTapSessionTests(t as object)
    t0 = 1700000000

    ' First ever session: id equals the start time, first-session flag is set, no prior
    ' session length, screen count starts at 1.
    storage = CleverTapFakeStorage()
    session = CleverTapSession(storage)
    startedNew = session.ensure(t0)
    t.isTrue(startedNew, "the first ensure starts a new session")
    m1 = session.meta()
    t.eq(m1.s, t0, "first session id is the start time")
    t.isTrue(m1.f, "first session flag is set")
    t.eq(m1.lsl, 0, "first session has no previous length")
    t.eq(m1.pg, 1, "screen count starts at 1")

    ' A fresh session's first batch is the first request; a successful upload clears it.
    t.isTrue(session.firstRequestInSession(), "a new session's first batch is a first request")
    session.markFirstRequestSent()
    t.isFalse(session.firstRequestInSession(), "a successful upload clears the first-request flag")

    ' An event a minute later is still the same session and no longer the first.
    startedNew = session.ensure(t0 + 60)
    t.isFalse(startedNew, "activity within the window does not start a new session")
    m2 = session.meta()
    t.eq(m2.s, t0, "activity within the window keeps the session")
    t.isFalse(session.firstRequestInSession(), "the flag stays cleared within the same session")

    ' An event past the 20-minute window starts a new session; it is not the first, and its
    ' previous-session length reflects the earlier session's span.
    later = t0 + 60 + (21 * 60)
    startedNew = session.ensure(later)
    t.isTrue(startedNew, "inactivity past the window starts a new session")
    m3 = session.meta()
    t.eq(m3.s, later, "inactivity starts a new session")
    t.isFalse(m3.f, "second session is not the first")
    t.eq(m3.lsl, 60, "previous session length is last activity minus its start")
    t.isTrue(session.firstRequestInSession(), "a new session re-arms the first-request flag")

    ' reset() forces the next event into a brand-new session (used on user switch).
    session.reset()
    even_later = later + 5
    startedNew = session.ensure(even_later)
    t.isTrue(startedNew, "reset forces a new session on the next ensure")
    t.eq(session.meta().s, even_later, "reset forces a new session on next event")
end function
