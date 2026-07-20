' Minimal test harness so the SDK's pure logic can be verified off-device with the
' BrightScript interpreter (no Roku hardware needed). Each suite receives a context,
' records assertions on it, and the runner prints a summary the CI wrapper checks.
function CTTest() as object
    return {
        passed: 0
        failed: 0
        failures: []

        ' Compares two values by their JSON form, which handles numbers, strings, arrays,
        ' and maps in one shot.
        eq: sub(actual as dynamic, expected as dynamic, msg as string)
            a = FormatJson(actual)
            e = FormatJson(expected)
            if a = e then
                m.passed++
            else
                m.failed++
                m.failures.Push(msg + " | expected " + e + " but got " + a)
            end if
        end sub

        isTrue: sub(value as dynamic, msg as string)
            if value = true then
                m.passed++
            else
                m.failed++
                m.failures.Push(msg + " | expected true")
            end if
        end sub

        isFalse: sub(value as dynamic, msg as string)
            if value = false then
                m.passed++
            else
                m.failed++
                m.failures.Push(msg + " | expected false")
            end if
        end sub

        ' Prints the outcome. The wrapper script looks for these exact markers.
        report: sub()
            for each f in m.failures
                print "  FAIL: " + f
            end for
            if m.failed = 0 then
                print "TESTS PASSED: " + m.passed.ToStr()
            else
                print "TESTS FAILED: " + m.failed.ToStr() + " of " + (m.passed + m.failed).ToStr()
            end if
        end sub
    }
end function
