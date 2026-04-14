Option Strict On
' CNC605 compliant: ReadOnly constants are safe; mutable state uses Interlocked for atomicity.

Imports System.Threading

Public Module CNC605_Compliant
    ' Compliant: ReadOnly Shared constant — no mutation, no race condition.
    Public Shared ReadOnly MaxBatchSize As Integer = 500

    ' Compliant: mutable counter uses Interlocked for atomic increment.
    Private Shared _counter As Integer = 0

    Public Sub RecordProcessed()
        Interlocked.Increment(_counter)
    End Sub

    Public Function GetCount() As Integer
        Return Interlocked.CompareExchange(_counter, 0, 0)
    End Function
End Module
