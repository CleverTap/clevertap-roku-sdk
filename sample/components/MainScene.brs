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
' profile, then record activity.
function ctBuildMenu() as object
    root = CreateObject("roSGNode", "ContentNode")
    labels = ["Login user", "Push profile", "Record event", "Record event with properties", "Record charged event", "Fire 3 events"]
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
    end if

    ' Show the CleverTap device id (GUID) so you can match this run to the dashboard profile
    ' without digging through the registry / Local Storage. onUserLogin can switch the id, so
    ' we read it after the call.
    id = ct.callfunc("getCleverTapID", invalid)
    if id <> "" then m.status.text = m.status.text + " | id " + id
end sub
