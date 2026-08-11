' Session tracking. A session groups the events a user fires in one sitting. It starts on
' the first event and ends after a stretch of inactivity; the next event after that starts
' a new one. Every event we upload carries the current session id plus a few counters the
' server uses for analytics.
'
' Session state lives in storage so a quick app restart resumes the same session instead of
' inventing a new one on every launch.

' Creates a session manager backed by the given storage.
function CleverTapSession(storage as object) as object
    return {
        storage: storage
        windowSeconds: CleverTapConstants().SESSION_LENGTH_MINS * 60

        ' Registry keys for the values we carry between events and across restarts.
        keyLastActivity: "sessLastActivity"  ' unix seconds of the most recent event
        keyId: "sessId"                       ' current session id
        keyStart: "sessStart"                 ' when the current session began
        keyLsl: "sessLsl"                     ' length of the previous session, in seconds
        keyIsFirst: "sessIsFirst"             ' 1 if the current session is the first ever
        keyPg: "sessPg"                        ' screen/activity counter within the session
        keyFirstDone: "sessFirstDone"         ' set once the very first session has happened

        ' Starts a new session or resumes the current one, based on how long it has been
        ' since the last event. Call this before reading meta() for an event. "now" is unix
        ' seconds, passed in so behaviour is easy to test.
        ensure: sub(now as integer)
            lastActivity = m._readInt(m.keyLastActivity)

            if lastActivity = invalid or (now - lastActivity) > m.windowSeconds then
                m._startNew(now)
            end if

            ' Touch the session so the inactivity window is measured from this event.
            m.storage.write(m.keyLastActivity, now.ToStr())
        end sub

        ' The per-event session fields: session id, screen count, previous session length,
        ' and whether this is the first-ever session.
        meta: function() as object
            return {
                s: m._readInt(m.keyId)
                pg: m._readInt(m.keyPg)
                lsl: m._readInt(m.keyLsl)
                f: m._readInt(m.keyIsFirst) = 1
            }
        end function

        ' Forces the next ensure() to begin a fresh session. Used when switching users so
        ' their events do not share a session with the previous user.
        reset: sub()
            m.storage.delete(m.keyLastActivity)
            m.storage.delete(m.keyId)
        end sub

        ' --- internals ---

        _startNew: sub(now as integer)
            ' The previous session's length feeds the next batch's analytics.
            prevStart = m._readInt(m.keyStart)
            prevActivity = m._readInt(m.keyLastActivity)
            lsl = 0
            if prevStart <> invalid and prevActivity <> invalid then lsl = prevActivity - prevStart

            isFirst = not m.storage.exists(m.keyFirstDone)
            if isFirst then m.storage.write(m.keyFirstDone, "1")

            m.storage.write(m.keyId, now.ToStr())
            m.storage.write(m.keyStart, now.ToStr())
            m.storage.write(m.keyLsl, lsl.ToStr())
            m.storage.write(m.keyPg, "1")
            m.storage.write(m.keyIsFirst, m._boolToStr(isFirst))
        end sub

        _readInt: function(key as string) as dynamic
            raw = m.storage.read(key)
            if raw = invalid then return invalid
            return raw.ToInt()
        end function

        _boolToStr: function(value as boolean) as string
            if value then return "1"
            return "0"
        end function
    }
end function
