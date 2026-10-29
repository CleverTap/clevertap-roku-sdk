' Identity resolution for onUserLogin. Decides whether identifying a user keeps the current
' device id or switches to a different one, so events land on the right person.
'
' The rules, in order:
'   - no identifier in the input      -> just update the current profile, no switch;
'   - device is still anonymous       -> claim the current id for this identity, no switch;
'   - identity already maps to current -> same user, no switch;
'   - identity maps to a known id      -> returning user, switch to that id;
'   - identity is new                  -> new user, switch to a freshly minted id.
'
' The identity -> id map ("identity cache") and the switch itself (clearing queues, resetting
' the session, swapping the id) live in the CleverTap node; this file is the pure decision so
' it can be tested off-device.

' Finds the first identity field present in the input, in configured priority order. Returns
' { key, value } with value as a string, or invalid if none is set.
'
' An identity has to become a string, because it is the lookup key for the device id. A
' number works. An array or an associative array does not. Such a value is skipped, and the
' next identity field is tried. The app is told through the log.
function CleverTapIdentityKeyValue(input as object) as dynamic
    if input = invalid then return invalid

    for each key in CleverTapConstants().IDENTITY_KEYS
        if input.DoesExist(key) then
            value = input[key]
            if value <> invalid then
                ' The type is checked before the value is compared to "". Comparing an array
                ' to a string raises a type mismatch and stops the channel.
                strValue = invalid
                if GetInterface(value, "ifString") <> invalid then
                    strValue = value
                else if GetInterface(value, "ifToStr") <> invalid then
                    strValue = value.ToStr()
                else
                    CleverTapLogError("identity field '" + key + "' was ignored. An identity must be text or a number.")
                end if

                if strValue <> invalid and strValue <> "" then
                    return { key: key, value: strValue }
                end if
            end if
        end if
    end for
    return invalid
end function

' Works out what identifying this user should do. Inputs:
'   input           - the attributes passed to onUserLogin (may hold an identity field)
'   currentDeviceId - the id in use right now
'   identified      - has any identity ever claimed this device?
'   cache           - the identity -> id map
'   newId           - a fresh id to use if this turns out to be a brand-new user
' Returns { action, deviceId, cacheKey, isNew }: deviceId is the id to use afterwards, and
' cacheKey is the "<Key>_<value>" entry to record (invalid when there's no identifier).
function CleverTapResolveLogin(input as object, currentDeviceId as string, identified as boolean, cache as object, newId as string) as object
    found = CleverTapIdentityKeyValue(input)
    if found = invalid then
        return { action: "profileOnly", deviceId: currentDeviceId, cacheKey: invalid, isNew: false }
    end if

    cacheKey = found.key + "_" + found.value

    ' Anonymous device: the current id becomes this identity's id. No switch.
    if not identified then
        return { action: "claim", deviceId: currentDeviceId, cacheKey: cacheKey, isNew: false }
    end if

    ' Identity already points at the current id: same user, nothing to do.
    if cache.DoesExist(cacheKey) and cache[cacheKey] = currentDeviceId then
        return { action: "same", deviceId: currentDeviceId, cacheKey: cacheKey, isNew: false }
    end if

    ' Different user. Reuse their id if we've seen them before, else take the fresh one.
    if cache.DoesExist(cacheKey) then
        return { action: "switch", deviceId: cache[cacheKey], cacheKey: cacheKey, isNew: false }
    end if
    return { action: "switch", deviceId: newId, cacheKey: cacheKey, isNew: true }
end function
