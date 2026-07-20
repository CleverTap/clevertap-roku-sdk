function CleverTapQueueTests(t as object)
    ' Profiles come out before events, capped at the batch size.
    storage = CleverTapFakeStorage()
    q = CleverTapQueue(storage)
    q.enqueueEvent({ tag: "e1" })
    q.enqueueEvent({ tag: "e2" })
    q.enqueueProfile({ tag: "p1" })

    t.eq(q.count(), 3, "queue counts events and profiles together")
    batch = q.nextBatch(49)
    t.eq([batch[0].tag, batch[1].tag, batch[2].tag], ["p1", "e1", "e2"], "profiles drain before events")

    ' The batch size caps how many items go out at once.
    t.eq(q.nextBatch(2).Count(), 2, "batch is capped at the requested size")

    ' Removing only the sent items leaves the rest for the next upload.
    q.removeSent(1)
    after = q.nextBatch(49)
    t.eq([after[0].tag, after[1].tag], ["e1", "e2"], "only the sent profile was removed")
    t.eq(q.count(), 2, "count reflects the removal")

    ' Cold start: a new queue over the same storage restores the saved items in order.
    q2 = CleverTapQueue(storage)
    q2.load()
    restored = q2.nextBatch(49)
    t.eq([restored[0].tag, restored[1].tag], ["e1", "e2"], "items survive a simulated restart")

    ' clear() empties both queues and their storage.
    q2.clear()
    q3 = CleverTapQueue(storage)
    q3.load()
    t.eq(q3.count(), 0, "clear wipes the persisted queue")

    ' A payload larger than one registry key is chunked and rebuilt intact.
    big = "x"
    for i = 1 to 16
        big = big + big
    end for
    t.isTrue(Len(big) > 30000, "test payload exceeds one chunk")
    qBig = CleverTapQueue(storage)
    qBig.enqueueEvent({ tag: "big", blob: big })
    qReload = CleverTapQueue(storage)
    qReload.load()
    reloaded = qReload.nextBatch(49)
    t.eq(reloaded[0].blob, big, "large chunked payload is restored exactly")
end function
