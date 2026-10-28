' Fake platform objects for off-device tests. They mimic just the methods the SDK calls on
' roDeviceInfo and roAppInfo, returning fixed values so tests stay deterministic.

function CTFakeDeviceInfo() as object
    return {
        GetOSVersion: function() as object
            return { major: "12", minor: "5", revision: "1", build: "4200" }
        end function
        GetDisplaySize: function() as object
            return { w: 1920, h: 1080 }
        end function
        GetModel: function() as string
            return "8000X"
        end function
        GetModelDisplayName: function() as string
            return "Roku Express 4K+"
        end function
        GetModelDetails: function() as object
            return { VendorName: "Roku", ModelNumber: "8000X", VendorUSBName: "", ScreenSize: "", Manufacturer: "" }
        end function
        GetCountryCode: function() as string
            return "US"
        end function
        GetCurrentLocale: function() as string
            return "en_US"
        end function
        GetTimeZone: function() as string
            return "US/Pacific"
        end function
    }
end function

' The same fake with a chosen time zone, including the case where the device reports none.
function CTFakeDeviceInfoWithTimeZone(timeZone as string) as object
    fake = CTFakeDeviceInfo()
    fake.timeZone = timeZone
    fake.GetTimeZone = function() as string
        return m.timeZone
    end function
    return fake
end function

' The same fake with a chosen maker and device name, for TVs that run Roku OS but are made
' by another company. Pass empty strings for a device that reports neither.
function CTFakeDeviceInfoAsTV(vendorName as string, displayName as string) as object
    fake = CTFakeDeviceInfo()
    fake.vendorName = vendorName
    fake.displayName = displayName
    fake.GetModelDisplayName = function() as string
        return m.displayName
    end function
    fake.GetModelDetails = function() as object
        return { VendorName: m.vendorName, ModelNumber: "8000X", VendorUSBName: "", ScreenSize: "55", Manufacturer: "" }
    end function
    return fake
end function

' The same fake with a chosen country code, for the cases where the device does not know
' the country.
function CTFakeDeviceInfoWithCountryCode(countryCode as string) as object
    fake = CTFakeDeviceInfo()
    fake.countryCode = countryCode
    fake.GetCountryCode = function() as string
        return m.countryCode
    end function
    return fake
end function

' roAppInfo stand-in whose GetValue returns supplied manifest values, mimicking real
' roAppInfo which returns "" for keys that aren't in the manifest.
function CTFakeManifestAppInfo(values as object) as object
    return {
        values: values
        GetVersion: function() as string
            return "1.2.0"
        end function
        GetValue: function(key as string) as string
            if m.values.DoesExist(key) then return m.values[key]
            return ""
        end function
    }
end function

function CTFakeAppInfo() as object
    return {
        GetVersion: function() as string
            return "1.2.0"
        end function
        GetValue: function(key as string) as string
            if key = "build_version" then return "42"
            return ""
        end function
    }
end function
