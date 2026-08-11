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
' The registry caps each key near 32KB, so a queue's JSON is split across numbered chunk
' keys and stitched back together on load.

' Creates a queue backed by the given storage.
function CleverTapQueue(storage as object) as object
    return {
        storage: storage
        events: []
        profiles: []

        ' Storage key prefixes for each queue's chunks.
        eventPrefix: "evtQ"
        profilePrefix: "prfQ"

        ' Max characters per chunk, kept under the registry's ~32KB per-key limit.
        chunkSize: 30000

        ' Drop the oldest item once a queue passes this many entries, so a device that is
        ' offline for a long time cannot grow the queue without bound.
        maxItems: 500

        ' Restores both queues from storage. Call once at startup.
        load: sub()
            m.events = m._load(m.eventPrefix)
            m.profiles = m._load(m.profilePrefix)
        end sub

        enqueueEvent: sub(item as object)
            m.events.Push(item)
            if m.events.Count() > m.maxItems then m.events.Shift()
            m._persist(m.eventPrefix, m.events)
        end sub

        enqueueProfile: sub(item as object)
            m.profiles.Push(item)
            if m.profiles.Count() > m.maxItems then m.profiles.Shift()
            m._persist(m.profilePrefix, m.profiles)
        end sub

        count: function() as integer
            return m.events.Count() + m.profiles.Count()
        end function

        isEmpty: function() as boolean
            return m.count() = 0
        end function

        ' The items to send next, profiles first, capped at the batch size. The server
        ' accepts a limited number per request; anything beyond goes out in later batches.
        nextBatch: function(maxSize as integer) as object
            combined = []
            for each p in m.profiles
                combined.Push(p)
            end for
            for each e in m.events
                combined.Push(e)
            end for

            batch = []
            for i = 0 to combined.Count() - 1
                if i >= maxSize then exit for
                batch.Push(combined[i])
            end for
            return batch
        end function

        ' Removes the first `sentCount` items in send order (profiles first, then events)
        ' after they upload successfully, and re-persists what is left. Only what was sent
        ' is removed, so items recorded during the upload survive.
        removeSent: sub(sentCount as integer)
            remaining = sentCount

            profilesToDrop = remaining
            if profilesToDrop > m.profiles.Count() then profilesToDrop = m.profiles.Count()
            for i = 1 to profilesToDrop
                m.profiles.Shift()
            end for
            remaining = remaining - profilesToDrop

            for i = 1 to remaining
                if m.events.Count() = 0 then exit for
                m.events.Shift()
            end for

            m._persist(m.profilePrefix, m.profiles)
            m._persist(m.eventPrefix, m.events)
        end sub

        ' Empties both queues and their storage. Used when the server tells us to stop.
        clear: sub()
            m.events = []
            m.profiles = []
            m._persist(m.eventPrefix, m.events)
            m._persist(m.profilePrefix, m.profiles)
        end sub

        ' --- internals ---

        ' Writes an array as JSON split across numbered chunk keys, plus a count key, and
        ' deletes any leftover chunks from a previously larger write.
        _persist: sub(prefix as string, items as object)
            oldCount = m._readInt(prefix + "_count")

            json = FormatJson(items)
            total = Len(json)
            idx = 0
            cursor = 1
            while cursor <= total
                m.storage.write(prefix + "_" + idx.ToStr(), Mid(json, cursor, m.chunkSize))
                cursor = cursor + m.chunkSize
                idx++
            end while
            m.storage.write(prefix + "_count", idx.ToStr())

            if oldCount <> invalid and oldCount > idx then
                for i = idx to oldCount - 1
                    m.storage.delete(prefix + "_" + i.ToStr())
                end for
            end if
        end sub

        ' Reads and reassembles an array previously written by _persist.
        _load: function(prefix as string) as object
            count = m._readInt(prefix + "_count")
            if count = invalid or count = 0 then return []

            json = ""
            for i = 0 to count - 1
                part = m.storage.read(prefix + "_" + i.ToStr())
                if part <> invalid then json = json + part
            end for

            parsed = ParseJson(json)
            if parsed = invalid then return []
            return parsed
        end function

        _readInt: function(key as string) as dynamic
            raw = m.storage.read(key)
            if raw = invalid then return invalid
            return raw.ToInt()
        end function
    }
end function
