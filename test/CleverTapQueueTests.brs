function CleverTapQueueTests(t as object)
    ' Profiles come out before events, capped at the batch size.
    storage = CleverTapFakeStorage()
    q = CleverTapQueue(storage)
    q.enqueueEvent({ tag: "e1" })
    q.enqueueEvent({ tag: "e2" })
    q.enqueueProfile({ tag: "p1" })

    t.eq(q.count(), 3, "queue counts events and profiles together")
    batch = q.nextBatch(49)
    t.eq([batch.items[0].tag, batch.items[1].tag, batch.items[2].tag], ["p1", "e1", "e2"], "profiles drain before events")
    ' e1 and e2 were recorded first, so they hold 1 and 2, and p1 holds 3.
    t.eq(batch.profileSeq, 3, "the batch reports the last profile it took")
    t.eq(batch.eventSeq, 2, "the batch reports the last event it took")

    ' The batch size caps how many items go out at once.
    t.eq(q.nextBatch(2).items.Count(), 2, "batch is capped at the requested size")

    ' Removing only the sent items leaves the rest for the next upload.
    q.removeSent(3, 0)
    after = q.nextBatch(49).items
    t.eq([after[0].tag, after[1].tag], ["e1", "e2"], "only the sent profile was removed")
    t.eq(q.count(), 2, "count reflects the removal")

    ' Cold start: a new queue over the same storage restores the saved items in order.
    q2 = CleverTapQueue(storage)
    q2.load()
    restored = q2.nextBatch(49).items
    t.eq([restored[0].tag, restored[1].tag], ["e1", "e2"], "items survive a simulated restart")

    ' clear() empties both queues and their storage.
    q2.clear()
    q3 = CleverTapQueue(storage)
    q3.load()
    t.eq(q3.count(), 0, "clear wipes the persisted queue")

    ' A payload that still fits the budget survives a reload unchanged.
    blob = "x"
    for i = 1 to 11
        blob = blob + blob
    end for
    t.isTrue(Len(blob) < 4000, "test payload fits the budget")
    qBig = CleverTapQueue(storage)
    qBig.enqueueEvent({ tag: "big", blob: blob })
    qReload = CleverTapQueue(storage)
    qReload.load()
    t.eq(qReload.nextBatch(49).items[0].blob, blob, "a large payload is restored exactly")

    CleverTapQueueMidUploadTests(t)
    CleverTapQueueBudgetTests(t)
end function

' An upload takes time. The app can record something while it runs. These checks cover what
' happens to that item.
function CleverTapQueueMidUploadTests(t as object)
    ' A profile is recorded while the upload is running. The upload then succeeds.
    q = CleverTapQueue(CleverTapFakeStorage())
    q.enqueueProfile({ tag: "p1" })
    q.enqueueProfile({ tag: "p2" })
    q.enqueueEvent({ tag: "e1" })
    q.enqueueEvent({ tag: "e2" })
    q.enqueueEvent({ tag: "e3" })

    batch = q.nextBatch(49)
    t.eq(batch.items.Count(), 5, "the whole queue fits in one batch")

    q.enqueueProfile({ tag: "p3" })
    q.removeSent(batch.profileSeq, batch.eventSeq)

    t.eq(q.count(), 1, "one item is left, the one recorded during the upload")
    left = q.nextBatch(49).items
    t.eq(left[0].tag, "p3", "the item recorded during the upload is still queued")

    ' The same check for an event recorded during the upload.
    q2 = CleverTapQueue(CleverTapFakeStorage())
    q2.enqueueProfile({ tag: "p1" })
    q2.enqueueEvent({ tag: "e1" })

    batch2 = q2.nextBatch(49)
    q2.enqueueEvent({ tag: "e2" })
    q2.removeSent(batch2.profileSeq, batch2.eventSeq)

    left2 = q2.nextBatch(49).items
    t.eq(q2.count(), 1, "only the event recorded during the upload is left")
    t.eq(left2[0].tag, "e2", "the event recorded during the upload is still queued")

    ' A batch smaller than the queue removes only its own share of each queue.
    q3 = CleverTapQueue(CleverTapFakeStorage())
    q3.enqueueProfile({ tag: "p1" })
    q3.enqueueProfile({ tag: "p2" })
    q3.enqueueEvent({ tag: "e1" })
    q3.enqueueEvent({ tag: "e2" })

    small = q3.nextBatch(3)
    ' p1 and p2 hold 1 and 2, e1 and e2 hold 3 and 4. A batch of 3 takes both profiles and
    ' the first event.
    t.eq([small.profileSeq, small.eventSeq], [2, 3], "a short batch takes profiles first")
    q3.removeSent(small.profileSeq, small.eventSeq)

    rest = q3.nextBatch(49).items
    t.eq(q3.count(), 1, "the item that did not fit is still queued")
    t.eq(rest[0].tag, "e2", "the item that did not fit is the last event")

    CleverTapQueueCapTests(t)
end function

' The queue drops its oldest item once it is full. That drop happens while an upload may be
' running, so these checks cover what the upload removes afterwards.
function CleverTapQueueCapTests(t as object)
    ' Filling the queue on purpose makes the SDK report the drop. The console copy is
    ' switched off so that report stays out of the test output.
    CleverTapLogSetConsoleOutput(false)

    ' A budget wide enough for three of these entries and no more.
    q = CleverTapQueue(CleverTapFakeStorage())
    q.maxBytes = Len(FormatJson([{ seq: 1, item: { tag: "e1" } }])) * 3
    q.enqueueEvent({ tag: "e1" })
    q.enqueueEvent({ tag: "e2" })
    q.enqueueEvent({ tag: "e3" })

    batch = q.nextBatch(49)
    t.eq(batch.items.Count(), 3, "the full queue goes out in one batch")

    ' Recorded while the upload runs. The queue is already full, so e1 is dropped to make
    ' room, and every item left moves one place forward.
    q.enqueueEvent({ tag: "e4" })
    q.removeSent(batch.profileSeq, batch.eventSeq)

    left = q.nextBatch(49).items
    t.eq(q.count(), 1, "only the item recorded during the upload is left")
    t.eq(left[0].tag, "e4", "the drop off the front did not take the new item with it")

    ' Sequence numbers keep going up across a restart, so a reload cannot hand out a number
    ' that an upload on its way is about to remove.
    storage = CleverTapFakeStorage()
    q3 = CleverTapQueue(storage)
    q3.enqueueEvent({ tag: "e1" })
    q3.enqueueProfile({ tag: "p1" })

    q4 = CleverTapQueue(storage)
    q4.load()
    q4.enqueueEvent({ tag: "e2" })
    t.eq(q4.nextBatch(49).eventSeq, 3, "a reloaded queue carries on from the saved numbers")

    CleverTapLogSetConsoleOutput(true)
end function

' The registry is small and the channel that hosts the SDK shares it. These checks cover
' what happens as the room runs out.
function CleverTapQueueBudgetTests(t as object)
    ' Running the storage out of room on purpose makes the SDK report it. The console copy
    ' is switched off so those reports stay out of the test output.
    CleverTapLogSetConsoleOutput(false)

    ' The limit counts characters, not entries. A queue of small entries therefore holds
    ' more of them than a queue of large ones.
    qSmall = CleverTapQueue(CleverTapFakeStorage())
    qSmall.maxBytes = 1000
    for i = 1 to 60
        qSmall.enqueueEvent({ tag: "e" })
    end for

    qBig = CleverTapQueue(CleverTapFakeStorage())
    qBig.maxBytes = 1000
    for i = 1 to 60
        qBig.enqueueEvent({ tag: "e", note: "a much longer value than the other queue holds" })
    end for

    t.isTrue(qSmall.count() > qBig.count(), "a queue of small entries holds more of them than one of large entries")
    t.isTrue(Len(FormatJson(qSmall.nextBatch(999).items)) <= 1000, "the small queue stayed inside its budget")
    t.isTrue(Len(FormatJson(qBig.nextBatch(999).items)) <= 1000, "the large queue stayed inside its budget")

    ' The newest entries are the ones kept.
    qOrder = CleverTapQueue(CleverTapFakeStorage())
    qOrder.maxBytes = Len(FormatJson([{ seq: 1, item: { tag: "e01" } }])) * 2
    for i = 1 to 9
        qOrder.enqueueEvent({ tag: "e0" + i.ToStr() })
    end for
    kept = qOrder.nextBatch(49).items
    t.eq(kept[kept.Count() - 1].tag, "e09", "the newest entry is kept")

    ' A full registry must not lose what is already in memory. The items can still be
    ' uploaded; they just will not come back after a restart.
    full = CleverTapFakeStorage()
    qFull = CleverTapQueue(full)
    qFull.enqueueEvent({ tag: "before" })
    full.capacity = 10
    qFull.enqueueEvent({ tag: "after" })

    t.eq(qFull.count(), 2, "both items are still queued when the registry is full")
    t.eq(qFull.nextBatch(49).items[1].tag, "after", "the item recorded while the registry was full is still there")

    ' Once there is room again, the queue saves and reloads as usual.
    full.capacity = 32768
    qFull.enqueueEvent({ tag: "later" })
    qAfter = CleverTapQueue(full)
    qAfter.load()
    t.eq(qAfter.count(), 3, "the queue is saved again once the registry has room")

    ' The check above uses two short entries. They never reach minBytes, so they never
    ' reach the code that shrinks the saved copy. This one does reach it.
    '
    ' A refused write must leave every entry in memory. The SDK saves a smaller copy
    ' instead. Entries left out of that copy are still queued for upload.
    deep = CleverTapFakeStorage()
    qDeep = CleverTapQueue(deep)
    qDeep.maxBytes = 4000
    ' Room for two entries in the saved copy.
    qDeep.minBytes = 70
    for i = 1 to 9
        qDeep.enqueueEvent({ tag: "e0" + i.ToStr() })
    end for
    t.eq(qDeep.count(), 9, "nine short entries fit well under maxBytes")

    ' Room for a short value only. The whole queue is refused. The smaller copy fits.
    deep.capacity = 150
    qDeep.enqueueEvent({ tag: "e10" })

    t.eq(qDeep.count(), 10, "a refused write leaves every entry in memory")
    inMemory = qDeep.nextBatch(49).items
    t.eq([inMemory[0].tag, inMemory[9].tag], ["e01", "e10"], "the oldest entry survives a refused write")

    ' Only the newest entries reached storage. Those are the ones that come back.
    qReloaded = CleverTapQueue(deep)
    qReloaded.load()
    saved = qReloaded.nextBatch(49).items
    t.eq(qReloaded.count(), 2, "the saved copy holds what fits in minBytes")
    t.eq([saved[0].tag, saved[1].tag], ["e09", "e10"], "the saved copy keeps the newest entries")

    ' The storage reports what is left, so the SDK can warn before it runs out.
    room = CleverTapFakeStorage()
    room.capacity = 500
    t.eq(room.spaceAvailable(), 500, "an empty storage reports its whole capacity")
    room.write("k", "0123456789")
    t.eq(room.spaceAvailable(), 489, "space goes down by the key and the value together")
    t.isFalse(room.write("big", CleverTapRepeat("x", 600)), "a write that does not fit is refused")

    CleverTapLogSetConsoleOutput(true)
end function

' Returns text repeated until it is at least count characters long.
function CleverTapRepeat(text as string, count as integer) as string
    out = text
    while Len(out) < count
        out = out + out
    end while
    return out
end function
