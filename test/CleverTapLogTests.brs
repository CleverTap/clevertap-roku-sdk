function CleverTapLogTests(t as object)
    ' The console copy is noise in a test run, so it is switched off for the whole suite.
    CleverTapLogSetConsoleOutput(false)
    consts = CleverTapConstants()

    ' --- level names ---

    levels = CleverTapLogLevels()
    t.eq(CleverTapLogParseLevel("off"), levels.OFF, "parses 'off'")
    t.eq(CleverTapLogParseLevel("ERROR"), levels.ERROR, "level name ignores letter case")
    t.eq(CleverTapLogParseLevel("  debug  "), levels.DEBUG, "level name ignores surrounding spaces")
    t.eq(CleverTapLogParseLevel(""), levels.INFO, "an empty level name falls back to info")
    t.eq(CleverTapLogParseLevel(invalid), levels.INFO, "a missing level name falls back to info")
    t.eq(CleverTapLogParseLevel("loud"), levels.INFO, "an unknown level name falls back to info")

    ' --- what each level lets through ---

    CleverTapLogSetLevel("error")
    CleverTapLogClear()
    CleverTapLogError("e")
    CleverTapLogInfo("i")
    CleverTapLogDebug("d")
    atError = CleverTapLogLines()
    t.eq(atError.Count(), 1, "at level error only the error line is kept")
    t.eq(atError[0], "[CleverTap] ERROR e", "an error line is labelled so it stands out")

    CleverTapLogSetLevel("info")
    CleverTapLogClear()
    CleverTapLogError("e")
    CleverTapLogInfo("i")
    CleverTapLogDebug("d")
    t.eq(CleverTapLogLines().Count(), 2, "at level info the debug line is dropped")
    t.eq(CleverTapLogLines()[1], "[CleverTap] i", "an info line carries no level label")

    CleverTapLogSetLevel("debug")
    CleverTapLogClear()
    CleverTapLogError("e")
    CleverTapLogInfo("i")
    CleverTapLogDebug("d")
    t.eq(CleverTapLogLines().Count(), 3, "at level debug every line is kept")

    CleverTapLogSetLevel("off")
    CleverTapLogClear()
    CleverTapLogError("e")
    t.eq(CleverTapLogLines().Count(), 0, "at level off nothing is kept")

    ' --- the stored lines ---

    CleverTapLogSetLevel("info")
    CleverTapLogClear()
    CleverTapLogInfo("one")
    CleverTapLogInfo("two")
    t.eq(CleverTapLogText(), "[CleverTap] one" + Chr(10) + "[CleverTap] two", "lines join with a newline, oldest first")

    ' The list holds a fixed number of lines. The oldest go first once it is full.
    CleverTapLogClear()
    for i = 1 to consts.LOG_BUFFER_LINES + 5
        CleverTapLogInfo(i.ToStr())
    end for
    kept = CleverTapLogLines()
    t.eq(kept.Count(), consts.LOG_BUFFER_LINES, "the list never grows past its limit")
    t.eq(kept[0], "[CleverTap] 6", "the oldest lines are dropped first")

    ' A long line is cut short in the list. An upload payload is the case that matters.
    CleverTapLogClear()
    long = ""
    for i = 1 to consts.LOG_MAX_LINE_CHARS + 100
        long = long + "x"
    end for
    CleverTapLogInfo(long)
    stored = CleverTapLogLines()[0]
    t.eq(Len(stored), consts.LOG_MAX_LINE_CHARS + 3, "a long line is cut to the limit plus an ellipsis")
    t.eq(Right(stored, 3), "...", "a cut line ends with an ellipsis")

    CleverTapLogClear()
    t.eq(CleverTapLogLines().Count(), 0, "clear empties the list")
    t.eq(CleverTapLogText(), "", "an empty list reads as an empty string")

    ' --- the level the SDK is configured with ---

    appInfo = CTFakeManifestAppInfo({ "clevertap_log_level": "debug" })
    fromManifest = CleverTapResolveCredentials({ accountId: "a", token: "b" }, appInfo)
    t.eq(fromManifest.logLevel, "debug", "the log level can come from the manifest")

    fromConfig = CleverTapResolveCredentials({ accountId: "a", token: "b", logLevel: "error" }, appInfo)
    t.eq(fromConfig.logLevel, "error", "a log level in the config beats the manifest")

    noLevel = CleverTapResolveCredentials({ accountId: "a", token: "b" }, CTFakeManifestAppInfo({}))
    t.eq(noLevel.logLevel, "", "no log level anywhere comes back empty")

    ' This suite changes global logger state, so it puts the defaults back when it is done.
    CleverTapLogClear()
    CleverTapLogSetLevel("info")
    CleverTapLogSetConsoleOutput(true)
end function
