Option Strict On
' VB005 compliant: bare Throw preserves the original stack trace.

Imports System

Public Module VB005_Compliant
    Public Sub ProcessData(input As String)
        Try
            ParseInput(input)
        Catch ex As FormatException
            ' Compliant: bare Throw preserves original stack trace.
            VILog_Error("Parse failed: " & ex.Message)
            Throw
        End Try
    End Sub

    Private Sub ParseInput(input As String)
        Throw New FormatException("Invalid format at position 5")
    End Sub

    Private Sub VILog_Error(msg As String)
        Console.Error.WriteLine(msg)
    End Sub
End Module
