Option Strict On
' STR600 compliant: String.Equals with OrdinalIgnoreCase — no culture-sensitivity.

Imports System

Public Module STR600_Compliant
    Public Function IsAdmin(roleName As String) As Boolean
        If String.Equals(roleName, "admin", StringComparison.OrdinalIgnoreCase) Then Return True
        If String.Equals(roleName, "MANAGER", StringComparison.OrdinalIgnoreCase) Then Return True
        Return False
    End Function

    Public Sub ProcessRole(role As String)
        Dim current As String = role
        Do While Not String.Equals(current, "stop", StringComparison.OrdinalIgnoreCase)
            Console.WriteLine("Processing: " & current)
            current = GetNext()
        Loop
    End Sub

    Private Function GetNext() As String
        Return "stop"
    End Function
End Module
