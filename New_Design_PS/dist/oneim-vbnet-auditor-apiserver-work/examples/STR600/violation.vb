Option Strict On
' STR600 violation: .ToLower() / .ToUpper() used in comparison context.
' In Turkish locale, "I".ToLower() returns the dotless-i character, not "i".

Imports System

Public Module STR600_Violation
    Public Function IsAdmin(roleName As String) As Boolean
        ' VIOLATION: ToLower() comparison is culture-sensitive.
        If roleName.ToLower() = "admin" Then Return True

        ' VIOLATION: ToUpper() comparison on right side, inside If.
        If "MANAGER" = roleName.ToUpper() Then Return True

        Return False
    End Function

    Public Sub ProcessRole(role As String)
        ' VIOLATION: ToLower inside While condition.
        Dim current As String = role
        While current.ToLower() <> "stop"
            Console.WriteLine("Processing: " & current)
            current = GetNext()
        End While
    End Sub

    Private Function GetNext() As String
        Return "stop"
    End Function
End Module
