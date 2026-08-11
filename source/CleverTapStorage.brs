' Thin wrapper over the Roku registry so the rest of the SDK reads and writes durable
' values through one small interface instead of touching roRegistrySection directly.
' Everything the SDK must survive an app restart (device id, queued events, identity
' cache) goes through here.
'
' The registry is the only storage on Roku that persists across reboots. Writes are
' buffered until flush() is called, so callers that change several keys pay one disk hit.
'
' Keeping this behind an interface also means tests can swap in an in-memory fake with the
' same shape (see CleverTapFakeStorage).
function CleverTapStorage(sectionName as string) as object
    return {
        section: CreateObject("roRegistrySection", sectionName)

        ' Returns the stored string, or invalid if the key was never set.
        read: function(key as string) as dynamic
            if m.section.Exists(key) then return m.section.Read(key)
            return invalid
        end function

        write: sub(key as string, value as string)
            m.section.Write(key, value)
            m.section.Flush()
        end sub

        delete: sub(key as string)
            m.section.Delete(key)
            m.section.Flush()
        end sub

        exists: function(key as string) as boolean
            return m.section.Exists(key)
        end function
    }
end function

' In-memory stand-in for CleverTapStorage with the same interface. Used by unit tests that
' run off-device where the registry does not exist.
function CleverTapFakeStorage() as object
    return {
        data: {}

        read: function(key as string) as dynamic
            if m.data.DoesExist(key) then return m.data[key]
            return invalid
        end function

        write: sub(key as string, value as string)
            m.data[key] = value
        end sub

        delete: sub(key as string)
            m.data.Delete(key)
        end sub

        exists: function(key as string) as boolean
            return m.data.DoesExist(key)
        end function
    }
end function
