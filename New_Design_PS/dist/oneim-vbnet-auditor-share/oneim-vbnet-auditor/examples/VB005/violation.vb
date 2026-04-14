Option Strict On
' VB005 violation: Throw ex resets the stack trace to this line.
' Support staff will see the rethrow line, not the original failure site.

Imports System

Public Module VB005_Violation
    Public Sub ProcessData(input As String)
        Try
            ParseInput(input)
        Catch ex As Exception
            ' VIOLATION: Throw ex destroys the original stack trace.
            Throw ex
        End Try
    End Sub

    Private Sub ParseInput(input As String)
        Throw New FormatException("Invalid format at position 5")
    End Sub
End Module
