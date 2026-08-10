' Network worker node. Scaffolding only for now; the handshake + upload logic lands on the
' task-network branch. init() runs on the render thread when the node is created; the actual
' work will run on the task thread inside the function named by m.top.functionName.
sub init()
    ' Intentionally empty until the task-network branch wires this up.
end sub
