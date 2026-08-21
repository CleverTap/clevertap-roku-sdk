function CleverTapMetaTests(t as object)
    storage = CleverTapFakeStorage()
    meta = CleverTapMeta(storage)

    ' A device that has never uploaded reports both timestamps as 0.
    s0 = meta.stamps()
    t.eq(s0.firstTs, 0, "first_ts starts at 0 before any upload")
    t.eq(s0.lastTs, 0, "last_ts starts at 0 before any upload")

    ' The first success sets both f_ts and l_ts to that time.
    meta.recordSuccess(1700000000)
    s1 = meta.stamps()
    t.eq(s1.firstTs, 1700000000, "first success sets first_ts")
    t.eq(s1.lastTs, 1700000000, "first success sets last_ts")

    ' A later success moves l_ts forward but leaves f_ts on the first upload.
    meta.recordSuccess(1700000500)
    s2 = meta.stamps()
    t.eq(s2.firstTs, 1700000000, "first_ts stays on the first-ever upload")
    t.eq(s2.lastTs, 1700000500, "last_ts moves to the most recent upload")
end function
