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
' The rows from "Remove profile value" down are the profile commands. Fire them from top to
' bottom to watch one list property being built up and then cut back down:
' [IND, AUS] -> [IND, AUS, ENG] -> [IND, AUS, ENG, NZ, SA] -> [IND, ENG, NZ, SA] -> [IND, ENG].
function ctBuildMenu() as object
    root = CreateObject("roSGNode", "ContentNode")
    labels = [
        "Login user",
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
        "Decrement points by 20"
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
        ct.callfunc("onUserLogin", [{ "Identity": "sample-user-1", "Email": "sam@example.com", "Name": "Sam" }])
        m.status.text = "onUserLogin fired for sample-user-1"
    else if index = 1 then
        ct.callfunc("profilePush", [{ "plan": "pro", "favTeam": "IND" }])
        m.status.text = "profilePush fired"
    else if index = 2 then
        ct.callfunc("recordEvent", ["Product viewed"])
        m.status.text = "recordEvent 'Product viewed' fired"
    else if index = 3 then
        ct.callfunc("recordEvent", ["Product viewed", { "id": 42, "name": "Bat" }])
        m.status.text = "recordEvent 'Product viewed' with properties fired"
    else if index = 4 then
        ct.callfunc("recordChargedEvent", [{ "Amount": 300 }, [{ "id": 1 }, { "id": 2 }]])
        m.status.text = "recordChargedEvent fired"
    else if index = 5 then
        ' Three events with no pause between them. The SDK waits one second after the last
        ' recorded event before it sends, so all three go in one request. The log shows one
        ' "sending:" line naming all three.
        for i = 1 to 3
            ct.callfunc("recordEvent", ["Product viewed", { "id": i }])
        end for
        m.status.text = "3 events fired, expect one request"
    else
        ' Rows 6 and up are the profile commands. They sit in their own sub to keep this one
        ' short.
        ctFireProfileCommand(ct, index)
    end if

    ' Show the CleverTap device id (GUID) so you can match this run to the dashboard profile
    ' without digging through the registry / Local Storage. onUserLogin can switch the id, so
    ' we read it after the call.
    id = ct.callfunc("getCleverTapID", invalid)
    if id <> "" then m.status.text = m.status.text + " | id " + id
end sub

' Fires one profile command. profilePush replaces the value of a key; these change one part
' of a value instead, so the channel does not have to read the old value first.
'
' Every call takes its arguments in the same order: the property name first, then the value.
' The property names are in quotes for the same reason the keys above are.
sub ctFireProfileCommand(ct as object, index as integer)
    if index = 6 then
        ' Takes the "plan" attribute off the profile. Press "Push profile" first to put it
        ' there.
        ct.callfunc("profileRemoveValueForKey", ["plan"])
        m.status.text = "profileRemoveValueForKey fired for plan"
    else if index = 7 then
        ' Replaces whatever "favTeams" held with this list.
        ct.callfunc("profileSetMultiValues", ["favTeams", ["IND", "AUS"]])
        m.status.text = "favTeams set to IND, AUS"
    else if index = 8 then
        ct.callfunc("profileAddMultiValue", ["favTeams", "ENG"])
        m.status.text = "ENG added to favTeams"
    else if index = 9 then
        ct.callfunc("profileAddMultiValues", ["favTeams", ["NZ", "SA"]])
        m.status.text = "NZ and SA added to favTeams"
    else if index = 10 then
        ct.callfunc("profileRemoveMultiValue", ["favTeams", "AUS"])
        m.status.text = "AUS removed from favTeams"
    else if index = 11 then
        ct.callfunc("profileRemoveMultiValues", ["favTeams", ["NZ", "SA"]])
        m.status.text = "NZ and SA removed from favTeams"
    else if index = 12 then
        ct.callfunc("profileIncrementValueBy", ["points", 50])
        m.status.text = "points raised by 50"
    else if index = 13 then
        ' The amount is how far to move the value, so it is positive here too. A negative
        ' amount is rejected.
        ct.callfunc("profileDecrementValueBy", ["points", 20])
        m.status.text = "points lowered by 20"
    end if
end sub
