Option Strict On
' REL210 violation: Culture-sensitive string comparison for an identifier key.
' In a Turkish locale, String.Compare("I","i") returns not-equal using default culture.

Imports System

Public Module REL210_Violation
    Public Function IsSystemAccount(accountName As String) As Boolean
        ' VIOLATION: culture-sensitive comparison — breaks in Turkish locale.
        Return String.Compare(accountName, "SYSTEM", True) = 0
    End Function

    Public Sub TagAccounts(names As String())
        For Each n As String In names
            ' VIOLATION: = operator uses culture-default comparison.
            If n = "admin" Then
                Console.WriteLine("Found admin")
            End If
        Next
    End Sub
End Module
