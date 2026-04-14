Option Strict On
' PER400 compliant: Any() for emptiness check; Count() only when the count is actually needed.

Imports System.Collections.Generic
Imports System.Linq

Public Module PER400_Compliant
    Public Sub PrintStatus(accounts As IEnumerable(Of String))
        If accounts.Any() Then
            Console.WriteLine("Accounts found: " & accounts.Count().ToString())
        End If

        If Not accounts.Any() Then
            Console.WriteLine("No accounts.")
        End If
    End Sub
End Module
