' Covers turning a Roku time zone name into the standard one.
'
' Roku has its own names. A server cannot read them. Every name on Roku's list has to come out
' of the table as a name the server knows.
function CleverTapTimeZoneTests(t as object)
    table = CleverTapRokuTimeZoneTable()

    ' Roku documents 151 names. One of them, "Africa/WT", is not explained anywhere, so it is
    ' left out on purpose. The other 150 are all in the table.
    t.eq(table.Count(), 150, "every documented Roku name but one is in the table")

    ' --- the names that are broken today ---

    ' These are the ones that matter. A server reading the Roku name gets no offset from it and
    ' falls back to zero. The viewer is then placed in London.
    t.eq(CleverTapIanaTimeZone("Asia/India"), "Asia/Kolkata", "India")
    t.eq(CleverTapIanaTimeZone("Asia/China"), "Asia/Shanghai", "China")
    t.eq(CleverTapIanaTimeZone("Asia/Japan"), "Asia/Tokyo", "Japan")
    t.eq(CleverTapIanaTimeZone("Asia/Korea"), "Asia/Seoul", "Korea")
    t.eq(CleverTapIanaTimeZone("Europe/United Kingdom"), "Europe/London", "the United Kingdom")
    t.eq(CleverTapIanaTimeZone("Europe/France"), "Europe/Paris", "France")
    t.eq(CleverTapIanaTimeZone("Mexico/Central"), "America/Mexico_City", "central Mexico")

    ' Roku groups several countries under one name. The name it gives covers a whole offset.
    t.eq(CleverTapIanaTimeZone("Europe/Central European Time"), "Europe/Paris", "a group of countries on the same offset")
    t.eq(CleverTapIanaTimeZone("Europe/Greece/Finland"), "Europe/Athens", "a name with two countries in it")

    ' --- the names that already work ---

    ' These Roku names are also old standard names. They are still put through the table. A
    ' name must not depend on luck.
    t.eq(CleverTapIanaTimeZone("US/Pacific"), "America/Los_Angeles", "the US Pacific coast")
    t.eq(CleverTapIanaTimeZone("US/Hawaii"), "Pacific/Honolulu", "Hawaii")
    t.eq(CleverTapIanaTimeZone("Australia/NSW"), "Australia/Sydney", "New South Wales")

    ' --- a name that is already standard ---

    ' Roku writes the names in the Americas the standard way. They come back unchanged.
    t.eq(CleverTapIanaTimeZone("America/Sao_Paulo"), "America/Sao_Paulo", "a name Roku already writes the standard way")

    ' --- a plain offset ---

    ' Roku lets a viewer pick an offset instead of a place. The standard name for an offset
    ' carries the opposite sign. "Etc/GMT-5" is five hours ahead of London, not behind it.
    t.eq(CleverTapIanaTimeZone("Other/UTC+5"), "Etc/GMT-5", "five hours ahead")
    t.eq(CleverTapIanaTimeZone("Other/UTC-5"), "Etc/GMT+5", "five hours behind")
    t.eq(CleverTapIanaTimeZone("Other/UTC+0"), "Etc/GMT", "the same as London in winter")

    ' --- a name that is not on the list ---

    t.eq(CleverTapIanaTimeZone("Africa/WT"), "", "a name Roku does not explain gives nothing")
    t.eq(CleverTapIanaTimeZone("Mars/Olympus"), "", "a name that was never real gives nothing")
    t.eq(CleverTapIanaTimeZone(""), "", "no name gives nothing")

    ' --- what the device reports ---

    CleverTapLogSetConsoleOutput(false)
    t.eq(CleverTapDeviceTimeZone(CTFakeDeviceInfoWithTimeZone("Asia/India")), "Asia/Kolkata", "the device name is turned into the standard one")
    t.eq(CleverTapDeviceTimeZone(CTFakeDeviceInfoWithTimeZone("")), "", "a device reporting no zone sends none")

    ' A zone the SDK cannot place is dropped. Sending it would put a wrong time zone on the
    ' profile, and a wrong one is worse than none.
    t.eq(CleverTapDeviceTimeZone(CTFakeDeviceInfoWithTimeZone("Nowhere/Nothing")), "", "a zone the SDK cannot place is dropped")
    CleverTapLogSetConsoleOutput(true)

    ' --- every name leads somewhere ---

    ' No entry may be empty, and no entry may still be a Roku name. A Roku name on the right
    ' would mean a name was copied instead of translated.
    '
    ' Four of Roku's groups start with a word the standard list never uses. A value starting
    ' with one of those four words was copied, not translated. The other groups share their
    ' first word with the standard list, so the first word alone proves nothing there.
    rokuOnlyPrefixes = ["Other/", "Mexico/", "US/", "Canada/"]
    emptyCount = 0
    rokuPrefixCount = 0
    for each rokuName in table
        mapped = table[rokuName]
        if mapped = "" or mapped = invalid then emptyCount = emptyCount + 1
        for each prefix in rokuOnlyPrefixes
            if Left(mapped, Len(prefix)) = prefix then rokuPrefixCount = rokuPrefixCount + 1
        end for
    end for
    t.eq(emptyCount, 0, "no name leads to an empty value")
    t.eq(rokuPrefixCount, 0, "no name leads to another Roku name")
end function
