' Brings up the SDK and a menu of its public calls. Each row fires one call on OK so you can
' watch that single request in the debug console and confirm it in the CleverTap dashboard.
sub init()
    ' ropm installs the SDK under its package prefix, so the node is "clevertaprokusdk_CleverTap".
    ct = CreateObject("roSGNode", "clevertaprokusdk_CleverTap")
    ' Keep it on m.global so any component in a real channel can reach it.
    m.global.addFields({ clevertap: ct })

    ' Credentials come from the manifest here (clevertap_account_id / _token / _region).
    ' To configure in code instead, pass them: init({ accountId: "...", token: "...", region: "in1" }).
    ct.callfunc("init", {})

    m.status = m.top.findNode("status")

    m.menu = m.top.findNode("menu")
    m.menu.content = ctBuildMenu()
    m.menu.observeField("itemSelected", "ctOnItemSelected")
    m.menu.setFocus(true)
end sub

' The menu rows, in the order they read best in a session: identify the user, then push a
' profile, then record activity, then change single profile properties.
'
' The first three rows are the login rows. Their names list the fields each one sends.
'
' Only three field names identify a user: Identity, Email and Phone. The SDK reads them in
' that order and the first one present wins. Rows A and B send an Email and no Identity, so
' Email is the field they are matched on. An Email identifies a user on its own.
' Name never identifies anyone. It is an ordinary attribute, which is what row C shows.
'
' onUserLogin can end in one of five ways, and which one it takes depends on what came before
' it. Press the rows in this order to walk through all five:
'
'   1. "Login A" on a device that has never been identified. The current device id is claimed
'      for user A. The id does not change.
'   2. "Login A" a second time. The identity already points at the current id, so nothing
'      happens beyond the profile update.
'   3. "Login B". A different user. No id is known for them, so a new one is made. The unsent
'      items of user A are dropped and a new session starts.
'   4. "Login A" again. User A is known, so the id made in step 1 comes back.
'   5. "Login C". No identifying field at all, so the attributes land on whoever is current
'      and no id is touched.
'
' The id shown at the end of the status line is how you tell these apart. Steps 3 and 4
' change it. Steps 1, 2 and 5 leave it alone.
'
' Step 1 only behaves this way on a device where the channel has never identified anyone. The
' claim is recorded permanently. After it, pressing "Login A" first takes the path in step 4
' instead.
'
' The rows from "Remove profile value" down are the profile commands. Fire them from top to
' bottom to watch one list property being built up and then cut back down:
' [IND, AUS] -> [IND, AUS, ENG] -> [IND, AUS, ENG, NZ, SA] -> [IND, ENG, NZ, SA] -> [IND, ENG].
'
' The last row is a diagnostic. It is not part of that session order.
function ctBuildMenu() as object
    root = CreateObject("roSGNode", "ContentNode")
    labels = [
        "Login A - Email, Name",
        "Login B - Email, Name",
        "Login C - Name only, no identifier",
        "Push profile",
        "Record event",
        "Record event with properties",
        "Record charged event",
        "Fire 3 events",
        "Remove profile value (plan)",
        "Set multi-values (IND, AUS)",
        "Add one multi-value (ENG)",
        "Add multi-values (NZ, SA)",
        "Remove one multi-value (AUS)",
        "Remove multi-values (NZ, SA)",
        "Increment points by 50",
        "Decrement points by 20",
        "Fill queue past the cap (40 events)"
    ]
    for each label in labels
        root.CreateChild("ContentNode").title = label
    end for
    return root
end function

sub ctOnItemSelected(event as object)
    ct = m.global.clevertap
    index = event.getData()

    ' Every key below is written in quotes. BrightScript treats an unquoted key in an
    ' associative array literal as an identifier, and identifiers are case-insensitive, so
    ' the device stores it in lowercase. CleverTap's server expects the exact spelling
    ' "Identity", "Email", "Name" and "Amount", so an unquoted key would arrive as a
    ' different field.
    if index = 0 then
        ct.callfunc("onUserLogin", [{ "Email": "sam@example.com", "Name": "Sam" }])
        m.status.text = "login A: Email sam@example.com, Name Sam"
    else if index = 1 then
        ct.callfunc("onUserLogin", [{ "Email": "bea@example.com", "Name": "Bea" }])
        m.status.text = "login B: Email bea@example.com, Name Bea"
    else if index = 2 then
        ' Name is an ordinary profile attribute, not an identifier. With no Identity, Email or
        ' Phone here the SDK has nobody to look up, so it leaves the device id alone and
        ' treats the call as a plain profile update.
        ct.callfunc("onUserLogin", [{ "Name": "Cas", "plan": "free" }])
        m.status.text = "login C: Name Cas, plan free. No identifier, so no user switch"
    else if index = 3 then
        ct.callfunc("profilePush", [{ "plan": "pro", "favTeam": "IND" }])
        m.status.text = "profilePush fired"
    else if index = 4 then
        ct.callfunc("recordEvent", ["Product viewed"])
        m.status.text = "recordEvent 'Product viewed' fired"
    else if index = 5 then
        ct.callfunc("recordEvent", ["Product viewed", { "id": 42, "name": "Bat" }])
        m.status.text = "recordEvent 'Product viewed' with properties fired"
    else if index = 6 then
        ct.callfunc("recordChargedEvent", [{ "Amount": 300 }, [{ "id": 1 }, { "id": 2 }]])
        m.status.text = "recordChargedEvent fired"
    else if index = 7 then
        ' Three events with no pause between them. The SDK waits one second after the last
        ' recorded event before it sends, so all three go in one request. The log shows one
        ' "sending:" line naming all three.
        for i = 1 to 3
            ct.callfunc("recordEvent", ["Product viewed", { "id": i }])
        end for
        m.status.text = "3 events fired, expect one request"
    else if index = 16 then
        ctFillQueuePastCap(ct)
    else
        ' Rows 8 to 15 are the profile commands. They sit in their own sub to keep this one
        ' short.
        ctFireProfileCommand(ct, index)
    end if

    ' Show the CleverTap device id (GUID) so you can match this run to the dashboard profile
    ' without digging through the registry / Local Storage. onUserLogin can switch the id, so
    ' we read it after the call.
    id = ct.callfunc("getCleverTapID", invalid)
    if id <> "" then m.status.text = m.status.text + " | id " + id
end sub

' Records enough events to push the event queue past the size it is allowed to reach. This
' row is a diagnostic. It does not demonstrate part of the public API.
'
' The queue may hold 8000 characters of JSON. It drops its oldest entries to stay under
' that. This row makes the drop happen on purpose.
'
' The padding is the point. One small event takes roughly 200 characters once the SDK has
' added the session fields. 40 small events would land near the limit. The result would be
' hard to read. Each event below takes roughly 350 characters instead. 40 of them reach
' roughly 14000 characters. The limit is then passed by a wide margin.
'
' Look for this line in the console. The SDK writes it once for each queue:
'   the event queue reached its 8000 character limit ...
'
' Two notes on what you will see:
'
' A successful upload empties the queue. The stored value would then be an empty list by
' the time you open the registry viewer. Put an account id that does not work in the
' manifest to stop the uploads. The log line above is written either way.
'
' 40 is below the 49 that trigger an immediate send. The SDK waits out its usual pause
' before it sends. Raise the count to 49 to watch a full batch leave in one request.
sub ctFillQueuePastCap(ct as object)
    pad = "0123456789012345678901234567890123456789"
    for i = 1 to 40
        ct.callfunc("recordEvent", ["Queue filler", { "id": i, "a": pad, "b": pad, "c": pad, "d": pad }])
    end for
    m.status.text = "40 padded events fired, check the log for the queue limit line"
end sub

' Fires one profile command. profilePush replaces the value of a key; these change one part
' of a value instead, so the channel does not have to read the old value first.
'
' Every call takes its arguments in the same order: the property name first, then the value.
' The property names are in quotes for the same reason the keys above are.
sub ctFireProfileCommand(ct as object, index as integer)
    if index = 8 then
        ' Takes the "plan" attribute off the profile. Press "Push profile" first to put it
        ' there.
        ct.callfunc("profileRemoveValueForKey", ["plan"])
        m.status.text = "profileRemoveValueForKey fired for plan"
    else if index = 9 then
        ' Replaces whatever "favTeams" held with this list.
        ct.callfunc("profileSetMultiValues", ["favTeams", ["IND", "AUS"]])
        m.status.text = "favTeams set to IND, AUS"
    else if index = 10 then
        ct.callfunc("profileAddMultiValue", ["favTeams", "ENG"])
        m.status.text = "ENG added to favTeams"
    else if index = 11 then
        ct.callfunc("profileAddMultiValues", ["favTeams", ["NZ", "SA"]])
        m.status.text = "NZ and SA added to favTeams"
    else if index = 12 then
        ct.callfunc("profileRemoveMultiValue", ["favTeams", "AUS"])
        m.status.text = "AUS removed from favTeams"
    else if index = 13 then
        ct.callfunc("profileRemoveMultiValues", ["favTeams", ["NZ", "SA"]])
        m.status.text = "NZ and SA removed from favTeams"
    else if index = 14 then
        ct.callfunc("profileIncrementValueBy", ["points", 50])
        m.status.text = "points raised by 50"
    else if index = 15 then
        ' The amount is how far to move the value, so it is positive here too. A negative
        ' amount is rejected.
        ct.callfunc("profileDecrementValueBy", ["points", 20])
        m.status.text = "points lowered by 20"
    end if
end sub
