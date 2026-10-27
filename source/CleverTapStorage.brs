' Thin wrapper over the Roku registry so the rest of the SDK reads and writes durable
' values through one small interface instead of touching roRegistrySection directly.
' Everything the SDK must survive an app restart (device id, queued events, identity
' cache) goes through here.
'
' The registry is the only storage on Roku that survives a reboot. It is also small, and
' the whole app shares it. Roku states: "The maximum size of each zlib-compressed
' application registry is 32K bytes." That budget covers our keys and every key the host
' channel keeps for itself, so the SDK has to stay a small guest inside it.
'
' Because the registry can fill up, write() reports whether the value was really stored.
' Callers must check it. Ignoring it would let the SDK carry on as if a value was saved
' when it was not.
'
' Keeping this behind an interface also means tests can swap in an in-memory fake with the
' same shape (see CleverTapFakeStorage).
function CleverTapStorage(sectionName as string) as object
    return {
        section: CreateObject("roRegistrySection", sectionName)
        ' GetSpaceAvailable lives on the registry itself, not on a section.
        registry: CreateObject("roRegistry")

        ' Returns the stored string, or invalid if the key was never set.
        read: function(key as string) as dynamic
            if m.section.Exists(key) then return m.section.Read(key)
            return invalid
        end function

        ' Returns true only when the value reached the registry. Both calls report success,
        ' and a full registry shows up as false from one of them.
        write: function(key as string, value as string) as boolean
            if not m.section.Write(key, value) then return false
            return m.section.Flush()
        end function

        delete: function(key as string) as boolean
            if not m.section.Delete(key) then return false
            return m.section.Flush()
        end function

        exists: function(key as string) as boolean
            return m.section.Exists(key)
        end function

        ' Bytes left in the app's 32K registry budget, counted after compression. Used to
        ' warn when the channel is nearly out of room.
        spaceAvailable: function() as integer
            return m.registry.GetSpaceAvailable()
        end function
    }
end function

' In-memory stand-in for CleverTapStorage with the same interface. Used by unit tests that
' run off-device where the registry does not exist.
'
' Set capacity to a small number to act like a registry that is nearly full. Writes that
' would go past it return false, the same answer the real registry gives.
function CleverTapFakeStorage() as object
    return {
        data: {}
        capacity: 32768

        read: function(key as string) as dynamic
            if m.data.DoesExist(key) then return m.data[key]
            return invalid
        end function

        write: function(key as string, value as string) as boolean
            was = 0
            if m.data.DoesExist(key) then was = Len(key) + Len(m.data[key])
            if m._used() - was + Len(key) + Len(value) > m.capacity then return false
            m.data[key] = value
            return true
        end function

        delete: function(key as string) as boolean
            m.data.Delete(key)
            return true
        end function

        exists: function(key as string) as boolean
            return m.data.DoesExist(key)
        end function

        spaceAvailable: function() as integer
            left = m.capacity - m._used()
            if left < 0 then return 0
            return left
        end function

        _used: function() as integer
            total = 0
            for each key in m.data
                total = total + Len(key) + Len(m.data[key])
            end for
            return total
        end function
    }
end function
