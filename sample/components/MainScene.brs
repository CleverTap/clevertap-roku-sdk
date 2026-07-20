' Starts the SDK and fires one of each call so you can verify the SDK end to end: watch the
' debug console for the outgoing requests and confirm the event, purchase, identified user,
' and profile show up in the CleverTap dashboard.
sub init()
    ct = CreateObject("roSGNode", "CleverTap")
    ' Keep it on m.global so any component in a real channel can reach it.
    m.global.addFields({ clevertap: ct })

    ' Credentials come from the manifest here (clevertap_account_id / _token / _region).
    ' To configure in code instead, pass them: init({ accountId: "...", token: "...", region: "in1" }).
    ct.callfunc("init", {})

    ' Identify the user first, then record a bit of activity for them.
    ct.callfunc("onUserLogin", [{ Identity: "sample-user-1", Email: "sam@example.com", Name: "Sam" }])
    ct.callfunc("profilePush", [{ plan: "pro", favTeam: "IND" }])
    ct.callfunc("recordEvent", ["Product viewed", { id: 42, name: "Bat" }])
    ct.callfunc("recordChargedEvent", [{ Amount: 300 }, [{ id: 1 }, { id: 2 }]])
end sub
