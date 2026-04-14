Option Strict On
' REL210 compliant: Explicit OrdinalIgnoreCase for identifier comparisons.

Imports System

Public Module REL210_Compliant
    Public Function IsSystemAccount(accountName As String) As Boolean
        Return String.Equals(accountName, "SYSTEM", StringComparison.OrdinalIgnoreCase)
    End Function

    Public Sub TagAccounts(names As String())
        For Each n As String In names
            If String.Equals(n, "admin", StringComparison.OrdinalIgnoreCase) Then
                Console.WriteLine("Found admin")
            End If
        Next
    End Sub
End Module
