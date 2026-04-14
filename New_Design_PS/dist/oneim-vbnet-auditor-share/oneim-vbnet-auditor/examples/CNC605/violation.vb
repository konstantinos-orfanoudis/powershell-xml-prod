Option Strict On
' CNC605 violation: Shared (static) mutable field without synchronisation.
' Two concurrent sync threads can read/write _counter simultaneously.

Public Module CNC605_Violation
    ' VIOLATION: Shared mutable field — race condition under concurrent provisioning.
    Private Shared _counter As Integer = 0
    Private Shared _lastProcessed As String = String.Empty

    Public Sub RecordProcessed(uid As String)
        _counter += 1
        _lastProcessed = uid
    End Sub

    Public Function GetCount() As Integer
        Return _counter
    End Function
End Module
