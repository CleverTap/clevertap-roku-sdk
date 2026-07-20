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
        GetCountryCode: function() as string
            return "US"
        end function
        GetCurrentLocale: function() as string
            return "en_US"
        end function
    }
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
