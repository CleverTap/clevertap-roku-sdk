' Builds a profile update: the item queued when the app sets attributes on the current user
' (name, email, plan, favourite team, ...). It rides in the same batch as events but in its
' own queue so profile changes reach the server first.
'
' The server recognises a fixed set of system fields (Name, Email, ...); anything else is a
' custom attribute. Both go into one flat "profile" object on the wire - the split only
' decides which keys we validate: system keys pass through as-is, custom keys are checked so
' an obviously bad key is dropped instead of poisoning the whole update.

' True if the key is one of the server's known system fields.
function CleverTapIsSystemProfileKey(key as string) as boolean
    for each known in CleverTapConstants().SYSTEM_PROFILE_KEYS
        if known = key then return true
    end for
    return false
end function

' Builds the profile item. fields is the attribute map from the app; sessionMeta supplies
' s/pg/lsl/f; epochSeconds is when it was recorded. Custom keys that fail validation are
' skipped (and logged); system keys are kept as given. A value the server cannot store is
' skipped as well, so it never replaces a value the server already holds.
'
' deviceCountryCode is the country of the device, or "" when the device reports none. It is
' only read by the phone number check. It defaults to "", which is the stricter of the two
' paths that check takes.
function CleverTapBuildProfile(fields as object, sessionMeta as object, epochSeconds as integer, deviceCountryCode = "" as string) as object
    validator = CleverTapValidator()
    consts = CleverTapConstants()
    profile = {}

    for each key in fields
        CleverTapWarnMiscasedKey(key, consts.PROFILE_RESERVED_KEYS, "profile field")
        ' Any letter case is checked here. A key spelled "phone" is reported above and still
        ' sent, so it still deserves the phone check.
        if LCase(key) = LCase(consts.PHONE_KEY) then
            CleverTapWarnPhoneNumber(fields[key], deviceCountryCode)
        end if
        value = CleverTapEncodeValue(key, fields[key])
        if value = invalid then
            ' Nothing to do. The value cannot be sent, and the reason for that was already
            ' reported. Leaving the key out is what protects the stored value.
        else if CleverTapIsSystemProfileKey(key) then
            profile[key] = value
        else
            check = validator.validatePropertyKey(key)
            if check.valid then
                profile[check.value] = value
            else
                CleverTapLogError("profile key rejected, " + check.message)
            end if
        end if
    end for

    return CleverTapWrapProfile(profile, sessionMeta, epochSeconds)
end function

' Puts a finished profile object into the item the queue stores. sessionMeta supplies
' s/pg/lsl/f; epochSeconds is when it was recorded.
function CleverTapWrapProfile(profile as object, sessionMeta as object, epochSeconds as integer) as object
    return {
        "type": "profile"
        "profile": profile
        "ep": epochSeconds
        "s": sessionMeta.s
        "pg": sessionMeta.pg
        "lsl": sessionMeta.lsl
        "f": sessionMeta.f
    }
end function

' --- profile commands ---
'
' A plain profile update replaces the value of a key. A command changes part of the value
' instead, so the app does not have to read the old value first. The server reads a command
' from the same profile object a plain update uses:
'
'     { "profile": { "favTeams": { "$add": ["IND"] } } }
'
' The SDK keeps no copy of the profile, so it never merges a command with the current value.
' It sends the command and the server applies it.

' Builds the item for one command. key names the property. command is one of the
' PROFILE_COMMAND_* values. value is already checked and shaped by the caller.
function CleverTapBuildProfileCommand(key as string, command as string, value as dynamic, sessionMeta as object, epochSeconds as integer) as object
    operation = {}
    operation[command] = value

    profile = {}
    profile[key] = operation

    return CleverTapWrapProfile(profile, sessionMeta, epochSeconds)
end function

' Describes one command in plain words, for the log. The command names themselves are wire
' tokens, so "$add" is never printed. command is one of the PROFILE_COMMAND_* values, key is
' the property name, and value is what is being sent.
function CleverTapDescribeProfileCommand(command as string, key as string, value as dynamic) as string
    consts = CleverTapConstants()

    if command = consts.PROFILE_COMMAND_DELETE then return key + " removed from the profile"
    if command = consts.PROFILE_COMMAND_INCREMENT then return key + " raised by " + value.ToStr()
    if command = consts.PROFILE_COMMAND_DECREMENT then return key + " lowered by " + value.ToStr()

    count = value.Count()
    noun = " values"
    if count = 1 then noun = " value"

    if command = consts.PROFILE_COMMAND_SET then return key + " set to " + count.ToStr() + noun
    if command = consts.PROFILE_COMMAND_ADD then return count.ToStr() + noun + " added to " + key
    return count.ToStr() + noun + " removed from " + key
end function

' Checks the key of a command. Returns { valid, value, message } like the other validators,
' where value is the trimmed key to use. Also reports a key spelled in the wrong letter case,
' which is a warning and does not make the key invalid.
function CleverTapValidateCommandKey(key as dynamic) as object
    check = CleverTapValidator().validatePropertyKey(key)
    if check.valid then
        CleverTapWarnMiscasedKey(check.value, CleverTapConstants().PROFILE_RESERVED_KEYS, "profile field")
    end if
    return check
end function

' Turns the values of a $set, $add or $remove into the list the server expects.
'
' A multi-value property holds strings, so every value is turned into a string. A value that
' cannot become a string, such as a nested array, is dropped. Values past
' MAX_MULTI_VALUE_COUNT are dropped too.
'
' Returns { valid, value, message }, where value is the finished list.
function CleverTapNormaliseMultiValues(values as dynamic) as object
    if values = invalid or GetInterface(values, "ifArray") = invalid then
        return { valid: false, value: [], message: "Multi-value property needs an array of values" }
    end if
    if values.Count() = 0 then
        return { valid: false, value: [], message: "Multi-value property has no values" }
    end if

    maxCount = CleverTapConstants().MAX_MULTI_VALUE_COUNT
    cleaned = []
    dropped = 0

    for each value in values
        if cleaned.Count() >= maxCount then
            dropped = dropped + 1
        else if value = invalid or GetInterface(value, "ifToStr") = invalid then
            ' An array or an associative array cannot be one value of a multi-value property.
            dropped = dropped + 1
        else if GetInterface(value, "ifString") <> invalid then
            cleaned.Push(value)
        else
            cleaned.Push(value.ToStr())
        end if
    end for

    if dropped > 0 then
        CleverTapLogError("multi-value property: " + dropped.ToStr() + " of " + values.Count().ToStr() + " values were dropped. A value must be text or a number, and at most " + maxCount.ToStr() + " values are kept.")
    end if

    if cleaned.Count() = 0 then
        return { valid: false, value: [], message: "Multi-value property has no usable values" }
    end if
    return { valid: true, value: cleaned, message: "" }
end function

' Checks the amount of an $incr or a $decr. The amount says how far to move the value, so it
' must be a number above zero. To lower a value, use the decrement call rather than a
' negative amount.
'
' Returns { valid, value, message }, where value is the amount to send.
function CleverTapValidateCommandAmount(amount as dynamic) as object
    isNumber = false
    if amount <> invalid then
        isNumber = (GetInterface(amount, "ifInt") <> invalid) or (GetInterface(amount, "ifFloat") <> invalid) or (GetInterface(amount, "ifDouble") <> invalid) or (GetInterface(amount, "ifLongInt") <> invalid)
    end if
    if not isNumber then
        return { valid: false, value: 0, message: "Amount must be a number" }
    end if
    if amount <= 0 then
        return { valid: false, value: amount, message: "Amount must be greater than zero" }
    end if
    return { valid: true, value: amount, message: "" }
end function
