' Channel entry point. Brings up the one scene and waits for the app to be closed.
sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    screen.CreateScene("MainScene")
    screen.Show()

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent" then
            if msg.IsScreenClosed() then return
        end if
    end while
end sub
