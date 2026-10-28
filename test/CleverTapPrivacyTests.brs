' Covers the opt-out choice: what it means, what it lets through, and how it is kept.
'
' A viewer who opts out has a legal right to be left alone. A mistake here is not a wrong
' number on a chart. It is reporting someone who asked not to be reported.
function CleverTapPrivacyTests(t as object)

    ' --- the starting state ---

    ' An app that never calls setOptOut sends everything. This matches the mobile SDKs. An
    ' app that wants the opposite has to ask for it.
    start = CleverTapPrivacyDefault()
    t.isFalse(start.optedOut, "a new install is opted in")
    t.isTrue(start.allowSystemEvents, "a new install sends everything")

    ' --- working out the state from the call ---

    ' One argument means a full opt-out. This is the common call, and it has to be the
    ' strongest one. An app that writes setOptOut(true) means "stop".
    full = CleverTapPrivacyResolve(true, false)
    t.isTrue(full.optedOut, "setOptOut(true) opts out")
    t.isFalse(full.allowSystemEvents, "setOptOut(true) stops the SDK's own events too")

    partial = CleverTapPrivacyResolve(true, true)
    t.isTrue(partial.optedOut, "the second argument does not change the opt-out itself")
    t.isTrue(partial.allowSystemEvents, "the SDK's own events can be kept")

    ' Asking to block system events while opted in is a contradiction. An opted-in viewer is
    ' sent everything. The flag is forced rather than stored, so no state can exist that
    ' setOptOut could never produce.
    backIn = CleverTapPrivacyResolve(false, false)
    t.isFalse(backIn.optedOut, "setOptOut(false) opts back in")
    t.isTrue(backIn.allowSystemEvents, "an opted-in viewer is always sent everything")

    ' --- what the server is told ---

    ' These two names are read by the server. They are the names the mobile SDKs send. A
    ' typo here means the server never learns about the opt-out.
    fields = CleverTapPrivacyProfileFields(full)
    t.eq(fields["ct_optout"], true, "the server is told about the opt-out")
    t.eq(fields["ct_allow_sys_events_and_communication"], false, "the server is told the SDK's own events stopped too")
    t.eq(fields.Count(), 2, "nothing else rides along")

    backInFields = CleverTapPrivacyProfileFields(backIn)
    t.eq(backInFields["ct_optout"], false, "opting back in is reported too")
    t.eq(backInFields["ct_allow_sys_events_and_communication"], true, "and so is everything resuming")

    ' --- what gets through ---

    ' Opted in: everything.
    t.isTrue(CleverTapPrivacyAllows("event", "Movie Played", start), "an opted-in viewer sends app events")
    t.isTrue(CleverTapPrivacyAllows("event", "App Launched", start), "an opted-in viewer sends SDK events")
    t.isTrue(CleverTapPrivacyAllows("profile", "", start), "an opted-in viewer sends profile changes")

    ' Opted out fully: nothing. Not even the SDK's own events.
    t.isFalse(CleverTapPrivacyAllows("event", "Movie Played", full), "a full opt-out stops app events")
    t.isFalse(CleverTapPrivacyAllows("event", "App Launched", full), "a full opt-out stops SDK events")
    t.isFalse(CleverTapPrivacyAllows("profile", "", full), "a full opt-out stops profile changes")

    ' Opted out, system events allowed: the app's events stop, the SDK's keep going.
    t.isFalse(CleverTapPrivacyAllows("event", "Movie Played", partial), "a partial opt-out stops app events")
    t.isTrue(CleverTapPrivacyAllows("event", "App Launched", partial), "a partial opt-out keeps SDK events")

    ' A profile change has to survive a partial opt-out. The opt-out is itself reported as a
    ' profile change. Blocking those would block the message that reports the opt-out.
    t.isTrue(CleverTapPrivacyAllows("profile", "", partial), "a partial opt-out keeps profile changes")

    ' --- which events count as the SDK's own ---

    t.isTrue(CleverTapPrivacyIsSystemEvent("App Launched"), "the SDK records App Launched itself")

    ' This is the one that is easy to get wrong. "Charged" is a name an app may not pass to
    ' recordEvent, because recordChargedEvent owns it. That does not make it the SDK's own
    ' event. A purchase is something the viewer did. A viewer who opted out does not expect
    ' their purchases to carry on being reported.
    t.isFalse(CleverTapPrivacyIsSystemEvent("Charged"), "a purchase is not the SDK's own event")
    t.isFalse(CleverTapPrivacyAllows("event", "Charged", partial), "a partial opt-out stops purchases")

    t.isFalse(CleverTapPrivacyIsSystemEvent("Movie Played"), "an app event is not the SDK's own event")

    ' --- keeping the choice ---

    ' The key carries the device id. Two viewers on one TV keep their own answer.
    t.eq(CleverTapPrivacyStorageKey("abc-123"), "optOut:abc-123", "the choice is kept against the device id")
    t.isTrue(CleverTapPrivacyStorageKey("one") <> CleverTapPrivacyStorageKey("two"), "two viewers do not share one answer")

    ' Two characters, because the registry is 32K for the whole app.
    t.eq(CleverTapPrivacyEncode(start), "01", "opted in")
    t.eq(CleverTapPrivacyEncode(full), "10", "opted out fully")
    t.eq(CleverTapPrivacyEncode(partial), "11", "opted out, SDK events kept")

    ' Reading back has to give what was written. A viewer does not opt out again on every
    ' launch.
    for each state in [start, full, partial]
        read = CleverTapPrivacyDecode(CleverTapPrivacyEncode(state))
        t.eq(read.optedOut, state.optedOut, "the opt-out survives a restart")
        t.eq(read.allowSystemEvents, state.allowSystemEvents, "the second flag survives a restart")
    end for

    ' Nothing kept yet, or something unreadable, reads as the starting state. A half-written
    ' entry must not read as some third thing.
    t.isFalse(CleverTapPrivacyDecode(invalid).optedOut, "a device with no answer is opted in")
    t.isFalse(CleverTapPrivacyDecode("").optedOut, "an empty entry is opted in")
    t.isFalse(CleverTapPrivacyDecode("1").optedOut, "a half-written entry is opted in")
    t.isFalse(CleverTapPrivacyDecode("yes please").optedOut, "an entry that was never ours is opted in")
    t.isFalse(CleverTapPrivacyDecode(7).optedOut, "an entry that is not text is opted in")

    ' A stored pair setOptOut could never produce is corrected on the way in.
    t.isTrue(CleverTapPrivacyDecode("00").allowSystemEvents, "an opted-in viewer always reads back as sending everything")

    ' --- what the log says ---

    ' These lines are read by a person integrating the SDK, so they say what happened rather
    ' than naming a flag.
    t.isTrue(Instr(1, CleverTapPrivacyDescribe(start), "opted in") > 0, "the log names the opted-in state")
    t.isTrue(Instr(1, CleverTapPrivacyDescribe(full), "nothing is sent") > 0, "the log says a full opt-out sends nothing")
    t.isTrue(Instr(1, CleverTapPrivacyDescribe(partial), "only the SDK") > 0, "the log says what a partial opt-out still sends")

    ' --- network details ---

    ' Off unless the app asks. The server is told not to read a location from the address the
    ' request came from.
    quiet = CleverTapDeviceAppFields(CTFakeDeviceInfo(), CTFakeAppInfo())
    t.eq(quiet["useIP"], false, "the server may not place the viewer by address")
    t.isTrue(quiet["wifi"] = invalid, "nothing about the connection is reported")

    ' On, and the device is on WiFi.
    onWifi = CleverTapDeviceAppFields(CTFakeDeviceInfoWithConnection("WiFiConnection"), CTFakeAppInfo(), true)
    t.eq(onWifi["useIP"], true, "the server may place the viewer by address once asked")
    t.eq(onWifi["wifi"], true, "a device on WiFi reports it")

    ' A TV joined by cable reports false. That is an answer, not a gap.
    onCable = CleverTapDeviceAppFields(CTFakeDeviceInfoWithConnection("WiredConnection"), CTFakeAppInfo(), true)
    t.eq(onCable["wifi"], false, "a device on a cable reports no WiFi")

    offline = CleverTapDeviceAppFields(CTFakeDeviceInfoWithConnection(""), CTFakeAppInfo(), true)
    t.eq(offline["wifi"], false, "a device with no connection reports no WiFi")
end function
