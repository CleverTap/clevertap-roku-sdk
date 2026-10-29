' Turns a Roku time zone name into the name the rest of the world uses.
'
' Roku does not use the standard time zone names. It has its own list of 151 names. Some of
' them look standard but are not. Roku says "Asia/India" where the standard name is
' "Asia/Kolkata". Roku says "Europe/United Kingdom" where the standard name is "Europe/London".
'
' A server that reads a name it does not know cannot work out the offset from it. It falls back
' to zero, which is the offset of London in winter. A viewer in India would then be treated as
' being 5 hours 30 minutes away from where they are. A message timed for 9 in the morning would
' reach them at half past two in the afternoon.
'
' 94 of the 151 names have this problem. The other 57 names happen to match an old standard
' name, so they already work. The table below covers every name on Roku's list. It is used for
' all of them, not only the broken ones. A name must not depend on luck.
'
' The list of names on the left comes from Roku's own documentation for GetTimeZone(). Every
' standard name on the right was checked against the time zone database.

' The standard name for a Roku time zone name. Returns "" when the name is not on Roku's list.
'
' An unknown name gives "" on purpose. The SDK then sends no time zone at all. A missing time
' zone falls back to the account time zone, which is close to right for most viewers. A wrong
' time zone is never close to right.
function CleverTapIanaTimeZone(rokuZone as string) as string
    if rokuZone = "" then return ""

    mapped = CleverTapRokuTimeZoneTable()[rokuZone]
    if mapped = invalid then return ""
    return mapped
end function

' The whole table, built when it is asked for.
'
' This is not kept in a field and not written to the registry. The SDK reads the time zone one
' time for each launch. The table is built for that one read. It is dropped straight after.
function CleverTapRokuTimeZoneTable() as object
    return {

        "US/Puerto Rico-Virgin Islands":    "America/Puerto_Rico"
        "US/Guam":                          "Pacific/Guam"
        "US/Samoa":                         "Pacific/Pago_Pago"
        "US/Hawaii":                        "Pacific/Honolulu"
        "US/Aleutian":                      "America/Adak"
        "US/Alaska":                        "America/Anchorage"
        "US/Pacific":                       "America/Los_Angeles"
        "US/Arizona":                       "America/Phoenix"
        "US/Mountain":                      "America/Denver"
        "US/Central":                       "America/Chicago"
        "US/Eastern":                       "America/New_York"
        "Canada/Pacific":                   "America/Vancouver"
        "Canada/Mountain":                  "America/Edmonton"
        "Canada/Central":                   "America/Winnipeg"
        "Canada/Eastern":                   "America/Toronto"
        "Canada/Mountain Standard":         "America/Dawson_Creek"
        "Canada/Central Standard":          "America/Regina"
        "Canada/Atlantic":                  "America/Halifax"
        "Canada/Newfoundland":              "America/St_Johns"
        "Mexico/Pacific":                   "America/Tijuana"
        "Mexico/Mountain":                  "America/Mazatlan"
        "Mexico/Central":                   "America/Mexico_City"
        "Mexico/Eastern":                   "America/Cancun"
        "America/Argentina/Buenos_Aires":   "America/Argentina/Buenos_Aires"
        "America/Santiago":                 "America/Santiago"
        "America/Bogota":                   "America/Bogota"
        "America/Costa_Rica":               "America/Costa_Rica"
        "America/El_Salvador":              "America/El_Salvador"
        "America/Guatemala":                "America/Guatemala"
        "America/Tegucigalpa":              "America/Tegucigalpa"
        "America/Managua":                  "America/Managua"
        "America/Panama":                   "America/Panama"
        "America/Lima":                     "America/Lima"
        "America/Campo_Grande":             "America/Campo_Grande"
        "America/Fortaleza":                "America/Fortaleza"
        "America/Manaus":                   "America/Manaus"
        "America/Noronha":                  "America/Noronha"
        "America/Rio_Branco":               "America/Rio_Branco"
        "America/Sao_Paulo":                "America/Sao_Paulo"
        "Europe/Iceland":                   "Atlantic/Reykjavik"
        "Europe/Ireland":                   "Europe/Dublin"
        "Europe/United Kingdom":            "Europe/London"
        "Europe/Portugal":                  "Europe/Lisbon"
        "Europe/Central European Time":     "Europe/Paris"
        "Europe/France":                    "Europe/Paris"
        "Europe/Greece/Finland":            "Europe/Athens"
        "Europe/Western European Time":     "Europe/Lisbon"
        "Australia/WA":                     "Australia/Perth"
        "Australia/Eucla":                  "Australia/Eucla"
        "Australia/NT":                     "Australia/Darwin"
        "Australia/SA":                     "Australia/Adelaide"
        "Australia/QLD":                    "Australia/Brisbane"
        "Australia/Lord Howe":              "Australia/Lord_Howe"
        "Australia/NSW":                    "Australia/Sydney"
        "Australia/VIC":                    "Australia/Melbourne"
        "Australia/TAS":                    "Australia/Hobart"
        "Australia/ACT":                    "Australia/Sydney"
        "Asia/Arabia":                      "Asia/Riyadh"
        "Asia/Afghanistan":                 "Asia/Kabul"
        "Asia/Alma-Ata":                    "Asia/Almaty"
        "Asia/Anadyr":                      "Asia/Anadyr"
        "Asia/Aqtobe":                      "Asia/Aqtobe"
        "Asia/Armenia":                     "Asia/Yerevan"
        "Asia/Azerbaijan":                  "Asia/Baku"
        "Asia/Bangladesh":                  "Asia/Dhaka"
        "Asia/Bhutan":                      "Asia/Thimphu"
        "Asia/Brunei":                      "Asia/Brunei"
        "Asia/China":                       "Asia/Shanghai"
        "Asia/Choibalsan":                  "Asia/Choibalsan"
        "Asia/EastTimor":                   "Asia/Dili"
        "Asia/Georgia":                     "Asia/Tbilisi"
        "Asia/Gulf":                        "Asia/Dubai"
        "Asia/Hong Kong":                   "Asia/Hong_Kong"
        "Asia/Hovd":                        "Asia/Hovd"
        "Asia/India":                       "Asia/Kolkata"
        "Asia/Indochina":                   "Asia/Bangkok"
        "Asia/Irkutsk":                     "Asia/Irkutsk"
        "Asia/Israel":                      "Asia/Jerusalem"
        "Asia/Japan":                       "Asia/Tokyo"
        "Asia/Kamchatka":                   "Asia/Kamchatka"
        "Asia/Korea":                       "Asia/Seoul"
        "Asia/Krasnoyarsk":                 "Asia/Krasnoyarsk"
        "Asia/Kyrgyzstan":                  "Asia/Bishkek"
        "Asia/Malaysia":                    "Asia/Kuala_Lumpur"
        "Asia/Magadan":                     "Asia/Magadan"
        "Asia/Myanmar":                     "Asia/Yangon"
        "Asia/Nepal":                       "Asia/Kathmandu"
        "Asia/Novosibirsk":                 "Asia/Novosibirsk"
        "Asia/Omsk":                        "Asia/Omsk"
        "Asia/Oral":                        "Asia/Oral"
        "Asia/Pakistan":                    "Asia/Karachi"
        "Asia/Philippines":                 "Asia/Manila"
        "Asia/Qyzylorda":                   "Asia/Qyzylorda"
        "Asia/Sakhalin":                    "Asia/Sakhalin"
        "Asia/Singapore":                   "Asia/Singapore"
        "Asia/Tajikistan":                  "Asia/Dushanbe"
        "Asia/Turkmenistan":                "Asia/Ashgabat"
        "Asia/Uzbekistan":                  "Asia/Tashkent"
        "Asia/Ulaanbaatar":                 "Asia/Ulaanbaatar"
        "Asia/Vladivostok":                 "Asia/Vladivostok"
        "Asia/Yakutsk":                     "Asia/Yakutsk"
        "Asia/Yekaterinburg":               "Asia/Yekaterinburg"
        "Asia/Eastern Indonesia":           "Asia/Jayapura"
        "Asia/Central Indonesia":           "Asia/Makassar"
        "Asia/Western Indonesia":           "Asia/Jakarta"
        "Asia/Beirut":                      "Asia/Beirut"
        "Asia/Damascus":                    "Asia/Damascus"
        "Asia/Gaza":                        "Asia/Gaza"
        "Asia/Nicosia":                     "Asia/Nicosia"
        "Africa/CAT":                       "Africa/Maputo"
        "Africa/CET":                       "Africa/Algiers"
        "Africa/CVT":                       "Atlantic/Cape_Verde"
        "Africa/EAT":                       "Africa/Nairobi"
        "Africa/EET":                       "Africa/Cairo"
        "Africa/GMT":                       "Africa/Abidjan"
        "Africa/MUT":                       "Indian/Mauritius"
        "Africa/RET":                       "Indian/Reunion"
        "Africa/SAST":                      "Africa/Johannesburg"
        "Africa/SCT":                       "Indian/Mahe"
        "Africa/WAST":                      "Africa/Windhoek"
        "Africa/WAT":                       "Africa/Lagos"
        "Africa/WEST":                      "Africa/Casablanca"
        "Africa/WET":                       "Africa/Casablanca"
        "Africa/WST":                       "Africa/El_Aaiun"
        "Other/UTC-11":                     "Etc/GMT+11"
        "Other/UTC-10":                     "Etc/GMT+10"
        "Other/UTC-9":                      "Etc/GMT+9"
        "Other/UTC-8":                      "Etc/GMT+8"
        "Other/UTC-7":                      "Etc/GMT+7"
        "Other/UTC-6":                      "Etc/GMT+6"
        "Other/UTC-5":                      "Etc/GMT+5"
        "Other/UTC-4":                      "Etc/GMT+4"
        "Other/UTC-3":                      "Etc/GMT+3"
        "Other/UTC-2":                      "Etc/GMT+2"
        "Other/UTC-1":                      "Etc/GMT+1"
        "Other/UTC+0":                      "Etc/GMT"
        "Other/UTC+1":                      "Etc/GMT-1"
        "Other/UTC+2":                      "Etc/GMT-2"
        "Other/UTC+3":                      "Etc/GMT-3"
        "Other/UTC+4":                      "Etc/GMT-4"
        "Other/UTC+5":                      "Etc/GMT-5"
        "Other/UTC+6":                      "Etc/GMT-6"
        "Other/UTC+7":                      "Etc/GMT-7"
        "Other/UTC+8":                      "Etc/GMT-8"
        "Other/UTC+9":                      "Etc/GMT-9"
        "Other/UTC+10":                     "Etc/GMT-10"
        "Other/UTC+11":                     "Etc/GMT-11"
        "Other/UTC+12":                     "Etc/GMT-12"
        "Other/UTC+13":                     "Etc/GMT-13"
        "Other/UTC+14":                     "Etc/GMT-14"
    }
end function
