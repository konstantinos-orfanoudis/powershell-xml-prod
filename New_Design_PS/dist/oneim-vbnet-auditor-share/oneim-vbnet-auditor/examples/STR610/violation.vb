Option Strict On
' STR610 violation: String.Format called with a variable as the format string.
' If the variable comes from user input or config, unexpected placeholders can throw
' a FormatException or expose internal values in error messages.

Public Module STR610_Violation
    Public Sub SendMessage(template As String, userName As String, count As Integer)
        ' VIOLATION: template is a variable — format injection risk.
        Dim message As String = String.Format(template, userName, count)
        Console.WriteLine(message)
    End Sub

    Public Sub LogEvent(formatMsg As String, value As Object)
        ' VIOLATION: formatMsg is a variable.
        Console.WriteLine(String.Format(formatMsg, value))
    End Sub
End Module
