Option Strict On
' STR610 compliant: String.Format with a string literal as the format argument.

Public Module STR610_Compliant
    Public Sub SendMessage(userName As String, count As Integer)
        ' Compliant: literal format string — no injection risk.
        Dim message As String = String.Format("Hello {0}, you have {1} items.", userName, count)
        Console.WriteLine(message)
    End Sub

    Public Sub LogEvent(value As Object)
        ' Compliant: literal format string.
        Console.WriteLine(String.Format("Event value: {0}", value))
    End Sub
End Module
