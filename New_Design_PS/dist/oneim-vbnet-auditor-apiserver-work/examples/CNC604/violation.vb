Option Strict On
' CNC604 violation: Unbounded loop (While True) with no iteration cap or timeout.
' If the exit condition is never met, the sync thread starves indefinitely.

Public Module CNC604_Violation
    Public Sub ProcessQueue(queue As System.Collections.Queue)
        ' VIOLATION: no iteration cap or timeout guard.
        While True
            If queue.Count > 0 Then
                Dim item = queue.Dequeue()
                Console.WriteLine("Processed: " & CStr(item))
            End If
        End While
    End Sub
End Module
