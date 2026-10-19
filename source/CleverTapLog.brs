' The one place that writes an SDK log line. Every line goes to two outputs. It is printed
' to the Roku debug console. It is also added to a short list kept in memory.
'
' The in-memory list exists for automated UI tests. A test running on a cloud device cannot
' read the debug console. The sample channel can show the list on screen instead. The test
' then reads that text off the screen.
'
' One function serves both outputs on purpose. Separate code used only by tests could drift
' away from what the SDK really prints. A second output of the real function cannot drift.
'
' State lives in GetGlobalAA() instead of in `m`. Most SDK modules are plain object
' literals. Inside their methods `m` is that object, not the node. GetGlobalAA() is
' reachable from every module with no plumbing.
'
' A note on threads. SceneGraph gives each thread its own GetGlobalAA(). Lines written on
' the task thread reach the debug console. They do not join the render thread's list.

' The levels, from quietest to loudest. A line is written when its own level is at or below
' the configured level.
function CleverTapLogLevels() as object
    return { OFF: 0, ERROR: 1, INFO: 2, DEBUG: 3 }
end function

' Turns a level name into its number. Any letter case is accepted. A missing or unknown
' name falls back to INFO.
function CleverTapLogParseLevel(name as dynamic) as integer
    levels = CleverTapLogLevels()
    if name = invalid then return levels.INFO
    if GetInterface(name, "ifString") = invalid then return levels.INFO

    lower = LCase(name.Trim())
    if lower = "off" then return levels.OFF
    if lower = "error" then return levels.ERROR
    if lower = "debug" then return levels.DEBUG
    return levels.INFO
end function

' The logger's own state. It is created on first use. A module may therefore log before
' init() has run.
function CleverTapLogState() as object
    gaa = GetGlobalAA()
    if gaa.ctLogState = invalid then
        gaa.ctLogState = {
            level: CleverTapLogLevels().INFO
            lines: []
            console: true
        }
    end if
    return gaa.ctLogState
end function

' Sets how much is logged. init() calls this once. levelName is "off", "error", "info" or
' "debug".
sub CleverTapLogSetLevel(levelName as dynamic)
    CleverTapLogState().level = CleverTapLogParseLevel(levelName)
end sub

' Turns the debug console copy on or off. The in-memory list is not affected. The off-device
' test run switches the console copy off. Hundreds of generated lines would otherwise bury
' the test results.
sub CleverTapLogSetConsoleOutput(enabled as boolean)
    CleverTapLogState().console = enabled
end sub

' Writes one line. Callers use the CleverTapLogError, CleverTapLogInfo and CleverTapLogDebug
' wrappers below rather than this function.
'
' Only errors carry a label. Normal lines are the common case, so naming their level on
' every line would be noise. An error has to stand out from them.
sub CleverTapLogWrite(level as integer, label as string, message as string)
    state = CleverTapLogState()
    if level > state.level then return

    consts = CleverTapConstants()
    line = "[CleverTap] "
    if label <> "" then line = line + label + " "
    line = line + message
    if state.console then print line

    ' The console gets the whole line. The stored copy is cut short. One very long line,
    ' such as an upload payload, would otherwise fill the whole on-screen label.
    stored = line
    if Len(stored) > consts.LOG_MAX_LINE_CHARS then
        stored = Left(stored, consts.LOG_MAX_LINE_CHARS) + "..."
    end if

    state.lines.Push(stored)
    while state.lines.Count() > consts.LOG_BUFFER_LINES
        state.lines.Shift()
    end while
end sub

' Something went wrong. Data may not reach CleverTap.
sub CleverTapLogError(message as string)
    CleverTapLogWrite(CleverTapLogLevels().ERROR, "ERROR", message)
end sub

' A normal thing the SDK did that an integrator would want to see.
sub CleverTapLogInfo(message as string)
    CleverTapLogWrite(CleverTapLogLevels().INFO, "", message)
end sub

' Detail that is only useful while debugging an integration.
sub CleverTapLogDebug(message as string)
    CleverTapLogWrite(CleverTapLogLevels().DEBUG, "", message)
end sub

' A copy of the stored lines, oldest first.
function CleverTapLogLines() as object
    copy = []
    for each line in CleverTapLogState().lines
        copy.Push(line)
    end for
    return copy
end function

' The stored lines joined into one string, one line per row. This is the shape the sample
' channel puts into a Label for a UI test to read.
function CleverTapLogText() as string
    text = ""
    for each line in CleverTapLogState().lines
        if text <> "" then text = text + Chr(10)
        text = text + line
    end for
    return text
end function

' Drops every stored line. Tests call this so one test cannot see another test's lines.
sub CleverTapLogClear()
    CleverTapLogState().lines = []
end sub
