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
' skipped (and logged); system keys are kept as given.
function CleverTapBuildProfile(fields as object, sessionMeta as object, epochSeconds as integer) as object
    validator = CleverTapValidator()
    profile = {}

    for each key in fields
        if CleverTapIsSystemProfileKey(key) then
            profile[key] = fields[key]
        else
            check = validator.validatePropertyKey(key)
            if check.valid then
                profile[check.value] = fields[key]
            else
                print "CleverTap: " + check.message
            end if
        end if
    end for

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
