' Tracks the two upload timestamps the batch meta header carries: f_ts (the first-ever
' successful upload) and l_ts (the most recent one). Both live in storage so they survive an
' app restart. They start at 0 on a fresh install - matching a device that has never reached
' the server - and only move once an upload actually succeeds.
'
' The mobile SDKs send these so the server can tell a brand-new device from a returning one;
' see CleverTapBuildMetaHeader for how they ride the header.
function CleverTapMeta(storage as object) as object
    return {
        storage: storage
        keyFirstTs: "firstTs"  ' unix seconds of the first-ever successful upload
        keyLastTs: "lastTs"    ' unix seconds of the most recent successful upload

        ' The { firstTs, lastTs } pair to send on the next batch. Both default to 0 until the
        ' first upload succeeds.
        stamps: function() as object
            return {
                firstTs: m._read(m.keyFirstTs)
                lastTs: m._read(m.keyLastTs)
            }
        end function

        ' Record a successful upload at "now" (unix seconds). l_ts always moves to the latest
        ' success; f_ts is written once and then left alone.
        recordSuccess: sub(now as integer)
            m.storage.write(m.keyLastTs, now.ToStr())
            if not m.storage.exists(m.keyFirstTs) then m.storage.write(m.keyFirstTs, now.ToStr())
        end sub

        _read: function(key as string) as integer
            raw = m.storage.read(key)
            if raw = invalid then return 0
            return raw.ToInt()
        end function
    }
end function
