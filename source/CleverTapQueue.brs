' Holds recorded items until they can be uploaded, and keeps them safe across restarts.
'
' There are two queues: one for profile updates and one for events. On upload they are
' combined with profiles first, so identity and profile changes reach the server before the
' events that depend on them.
'
' Every change is written straight to storage so nothing is lost if the app is killed
' before the next upload (for example, events recorded while offline). On launch, load()
' pulls the saved items back into memory.
'
' Each queued item is stored with a sequence number. The number only goes up, and it is
' never reused. An upload remembers the highest number it sent from each queue, and that
' number is what decides which entries to remove afterwards. See removeSent for why a
' position in the queue cannot be used for that.
'
' A whole queue is written to one storage key as a single JSON string. The size of that
' string is capped, because the whole app shares one 32KB registry, and that 32KB includes
' whatever the host channel keeps there as well.

' Creates a queue backed by the given storage.
function CleverTapQueue(storage as object) as object
    return {
        storage: storage
        events: []
        profiles: []

        ' The storage key each queue is saved under.
        eventKey: "evtQ"
        profileKey: "prfQ"

        ' The sequence number the next queued item will get. Shared by both queues, so a
        ' number identifies one entry across the whole queue. Starts at 1, because 0 is the
        ' watermark that means "this batch took nothing from that queue".
        nextSeq: 1

        ' Largest JSON size one queue may reach. The oldest entries are dropped to stay
        ' under it, so a device that is offline for a long time cannot grow the queue
        ' without bound.
        '
        ' The size is counted in characters, not in entries. A single event can be 162
        ' characters or 686, depending on how many properties the app attaches, so a limit
        ' counted in entries would let one app use four times the room of another. Counting
        ' characters keeps the SDK's share of the registry the same for every app.
        '
        ' Two queues at 8000 each is about 16KB of JSON. The registry stores it compressed,
        ' which measured at roughly 2.2KB, near 7% of the app's 32K budget. The rest is left
        ' for the channel that hosts the SDK.
        maxBytes: 8000

        ' Shrink a queue to this size and try again when the registry refuses a write. The
        ' refusal usually means the whole registry is full, so the SDK gives back most of
        ' its room and keeps only the newest entries.
        minBytes: 2000

        ' Holds the name of each queue that is dropping entries right now. A queue that has
        ' reached its limit drops an entry every time a new one arrives. One log line per
        ' drop would fill the console, so the message is written only when a queue starts
        ' dropping. The name is taken out again once the queue fits in its budget.
        dropNoted: {}

        ' Restores both queues from storage. Call once at startup.
        load: sub()
            m.profiles = m._load(m.profileKey)
            m.events = m._load(m.eventKey)
            ' Carry on from the highest number that was saved. Reusing a number would let
            ' one upload remove an item recorded by a later one.
            m.nextSeq = m._highestSeq() + 1
        end sub

        enqueueEvent: sub(item as object)
            m.events.Push({ seq: m.nextSeq, item: item })
            m.nextSeq++
            m._persist(m.eventKey, m.events, "event")
        end sub

        enqueueProfile: sub(item as object)
            m.profiles.Push({ seq: m.nextSeq, item: item })
            m.nextSeq++
            m._persist(m.profileKey, m.profiles, "profile")
        end sub

        count: function() as integer
            return m.events.Count() + m.profiles.Count()
        end function

        isEmpty: function() as boolean
            return m.count() = 0
        end function

        ' The items to send next, profiles first, capped at the batch size. The server
        ' accepts a limited number per request. Anything beyond that goes out in a later
        ' batch.
        '
        ' Returns { items, profileSeq, eventSeq }. Each seq is the highest sequence number
        ' the batch took from that queue, or 0 when it took nothing from it. Pass both back
        ' to removeSent once the upload succeeds.
        nextBatch: function(maxSize as integer) as object
            profileCount = m.profiles.Count()
            if profileCount > maxSize then profileCount = maxSize

            eventCount = maxSize - profileCount
            if eventCount > m.events.Count() then eventCount = m.events.Count()

            items = []
            profileSeq = 0
            for i = 0 to profileCount - 1
                items.Push(m.profiles[i].item)
                profileSeq = m.profiles[i].seq
            end for

            eventSeq = 0
            for i = 0 to eventCount - 1
                items.Push(m.events[i].item)
                eventSeq = m.events[i].seq
            end for

            return { items: items, profileSeq: profileSeq, eventSeq: eventSeq }
        end function

        ' Removes the items that have just been uploaded, then re-persists what is left.
        ' profileSeq and eventSeq come from the nextBatch call that built the batch. An
        ' entry is removed when its sequence number is at or below the watermark for its
        ' queue.
        '
        ' A sequence number is used here instead of a position, because a position does not
        ' stay still while the upload runs. The app can record an item during the upload,
        ' and that item is added to the back of its queue. The queue can also hit its size
        ' cap and drop an item off the front, which moves every remaining item one place
        ' forward. Either way the front of the queue no longer holds what it held when the
        ' batch was built. A sequence number belongs to one entry and never moves, so it
        ' names the same items either way.
        '
        ' The two numbers are kept apart because the two queues number from the same
        ' counter but drain separately. One watermark could not say where each queue ended.
        removeSent: sub(profileSeq as integer, eventSeq as integer)
            m.profiles = m._dropUpTo(m.profiles, profileSeq)
            m.events = m._dropUpTo(m.events, eventSeq)

            m._persist(m.profileKey, m.profiles, "profile")
            m._persist(m.eventKey, m.events, "event")
        end sub

        ' Empties both queues and their storage. Used when the server tells us to stop.
        clear: sub()
            m.events = []
            m.profiles = []
            m._persist(m.eventKey, m.events, "event")
            m._persist(m.profileKey, m.profiles, "profile")
        end sub

        ' --- internals ---

        ' Keeps only the entries numbered above the watermark. A watermark of 0 keeps
        ' everything, because sequence numbers start at 1.
        _dropUpTo: function(entries as object, watermark as integer) as object
            if watermark = 0 then return entries

            kept = []
            for each entry in entries
                if entry.seq > watermark then kept.Push(entry)
            end for
            return kept
        end function

        ' The largest sequence number held by either queue right now, or 0 when both are
        ' empty.
        _highestSeq: function() as integer
            highest = 0
            for each entry in m.profiles
                if entry.seq > highest then highest = entry.seq
            end for
            for each entry in m.events
                if entry.seq > highest then highest = entry.seq
            end for
            return highest
        end function

        ' Saves a queue to storage.
        '
        ' label names the queue in the log ("event" or "profile").
        '
        ' Two limits apply here, and they behave differently.
        '
        ' maxBytes is the real size of the queue. Entries past it leave memory as well as
        ' storage. This keeps a device that is offline for a long time from growing the
        ' queue without end.
        '
        ' minBytes applies only after storage refuses a write. The SDK then saves a smaller
        ' copy. The queue in memory is left whole. Every entry in it can still be uploaded.
        ' The entries missing from the saved copy are only the ones that will not come back
        ' after a restart.
        _persist: sub(key as string, items as object, label as string)
            ' This call is allowed to change the queue. See the note on maxBytes above.
            json = m._trim(items, m.maxBytes, label)
            if m.storage.write(key, json) then return

            ' The registry refused the write. It is almost always full. The channel that
            ' hosts the SDK shares the same 32K. Give most of the room back and try once.
            CleverTapLogError("could not save the " + label + " queue, the registry is full. " + m._spaceNote())

            ' This call must not change the queue. Only the saved copy gets smaller.
            smaller = m._tailJson(items, m.minBytes)
            if m.storage.write(key, smaller.json) then
                CleverTapLogInfo("saved the newest " + smaller.saved.ToStr() + " of " + items.Count().ToStr() + " " + label + " entries after making room. Every one of them is still queued for upload.")
                return
            end if

            CleverTapLogError("still could not save the " + label + " queue. " + items.Count().ToStr() + " entries are kept in memory only and will be lost if the channel closes.")
        end sub

        ' Drops the oldest entries until the JSON fits in budget. Returns that JSON, so the
        ' caller does not have to build it a second time.
        '
        ' This takes entries out of the array it is given. The caller passes the live queue,
        ' so the entries are gone from memory too. They can no longer be uploaded. Use
        ' _tailJson when the queue has to be left alone.
        _trim: function(items as object, budget as integer, label as string) as string
            json = FormatJson(items)

            ' An empty string means the writer refused the value. It is not the same as an
            ' empty queue, which is written as "[]". Saving it would put an empty string over
            ' a full queue and every entry waiting in it would be gone. Take out the entries
            ' the writer cannot write, so the rest are still saved.
            if json = "" and items.Count() > 0 then
                m._dropUnwritable(items, label)
                json = FormatJson(items)
                ' Still refused with nothing left to blame. Save an empty queue rather than
                ' an empty string, so what is read back on the next launch is a queue with
                ' nothing in it instead of something that cannot be read at all. The entries
                ' stay in memory and can still be uploaded in this run.
                if json = "" then
                    CleverTapLogError("the " + label + " queue cannot be written as JSON, so nothing was saved. Its entries are kept in memory and will be lost if the channel closes.")
                    return "[]"
                end if
            end if

            if Len(json) <= budget then
                ' The queue fits again. Allow the next log line if it fills up later.
                m.dropNoted.Delete(label)
                return json
            end if

            while Len(json) > budget and items.Count() > 1
                items.Shift()
                json = FormatJson(items)
            end while

            ' Already reported for this queue. Stay quiet until it has room again.
            if m.dropNoted.DoesExist(label) then return json
            m.dropNoted[label] = true

            ' One entry on its own can be larger than the whole budget. Dropping the others
            ' did not help, and there is nothing left to drop.
            if Len(json) > budget then
                CleverTapLogError("a single " + label + " takes " + Len(json).ToStr() + " characters, more than the " + budget.ToStr() + " the whole queue is allowed. It cannot be saved. Check how large the values are that the app attaches to it.")
                return json
            end if

            CleverTapLogInfo("the " + label + " queue reached its " + budget.ToStr() + " character limit, so the oldest entries are now dropped to make room for new ones. " + items.Count().ToStr() + " are still queued. This is reported once per queue.")
            return json
        end function

        ' Takes out the entries the JSON writer refuses. One such entry costs the whole
        ' queue, because the writer is given the queue as one value and answers with an empty
        ' string for all of it.
        '
        ' A value that holds itself is the usual cause. The SDK copies every value an app
        ' gives it, so such a value should not get this far. This is here because the price
        ' of missing one is every event the device has not sent yet.
        '
        ' The entries are removed from the array the caller passed. They leave memory as
        ' well, so no later save meets them again.
        _dropUnwritable: sub(items as object, label as string)
            kept = []
            for each entry in items
                if FormatJson(entry) <> "" then kept.Push(entry)
            end for

            dropped = items.Count() - kept.Count()
            if dropped = 0 then return

            items.Clear()
            for each entry in kept
                items.Push(entry)
            end for
            CleverTapLogError(dropped.ToStr() + " " + label + " entries hold a value the SDK cannot write as JSON, so they were dropped. The other " + items.Count().ToStr() + " are still queued.")
        end sub

        ' The JSON of the newest entries that fit in the budget. The array it is given is
        ' not changed, so every entry stays available for upload.
        '
        ' Returns { json, saved }. saved is how many entries the JSON holds. The field is
        ' not called "count", because roAssociativeArray already has a Count method, and
        ' that name would reach the method instead of this value.
        _tailJson: function(items as object, budget as integer) as object
            json = FormatJson(items)
            if Len(json) <= budget then return { json: json, saved: items.Count() }

            ' Leave out one more entry from the front each time until the rest fit.
            first = 1
            while first < items.Count()
                tail = []
                for i = first to items.Count() - 1
                    tail.Push(items[i])
                end for
                json = FormatJson(tail)
                if Len(json) <= budget then return { json: json, saved: tail.Count() }
                first++
            end while

            ' Not even the newest entry on its own fits. Hand back that one entry. The
            ' write will probably be refused as well. The caller reports that.
            return { json: json, saved: 1 }
        end function

        ' Reports the room left, when the storage can tell us. Older fakes and any storage
        ' without the call simply leave this out of the message.
        _spaceNote: function() as string
            if not m.storage.DoesExist("spaceAvailable") then return ""
            return "The app has " + m.storage.spaceAvailable().ToStr() + " bytes left of its 32K registry, shared with the channel."
        end function

        ' Reads back an array previously written by _persist.
        _load: function(key as string) as object
            json = m.storage.read(key)
            if json = invalid then return []

            parsed = ParseJson(json)
            if parsed = invalid then return []

            ' Keep only the entries that carry both a sequence number and an item. An entry
            ' in any other shape was written by a build that stored the queue differently.
            ' Its place in the order is unknown, so it is left out.
            entries = []
            for each entry in parsed
                if type(entry) = "roAssociativeArray" then
                    if entry.seq <> invalid and entry.item <> invalid then entries.Push(entry)
                end if
            end for
            return entries
        end function
    }
end function
