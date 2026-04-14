Option Strict On
' API600 violation: AwaitTasks explicitly enabled on an API Server event stream.

Public Module API600_Violation
    Public Sub Configure()
        Dim response = New ObservableEventStreamResponse() With {
            .AwaitTasks = True
        }
    End Sub
End Module
