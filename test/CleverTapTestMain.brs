' Entry point for the off-device test run. Builds one test context, runs every suite
' against it, and prints the summary. New suites get added here as modules land.
sub main()
    t = CTTest()

    CleverTapDeviceTests(t)
    CleverTapSessionTests(t)
    CleverTapQueueTests(t)
    CleverTapValidatorTests(t)
    CleverTapRequestTests(t)
    CleverTapMetaTests(t)
    CleverTapNetworkTests(t)
    CleverTapArpTests(t)
    CleverTapValueTests(t)
    CleverTapProfileTests(t)
    CleverTapLoginTests(t)
    CleverTapLogTests(t)

    t.report()
end sub
