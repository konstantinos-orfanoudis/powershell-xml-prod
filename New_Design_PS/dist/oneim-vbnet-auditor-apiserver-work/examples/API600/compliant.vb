Option Strict On
' API600 compliant: AwaitTasks stays disabled.

Public Module API600_Compliant
    Public Sub Configure()
        Dim response = New ObservableEventStreamResponse() With {
            .AwaitTasks = False
        }
    End Sub
End Module
