Option Strict On
' PER400 violation: Count() used just to check whether a sequence is empty.
' Count() enumerates the whole sequence; Any() stops at the first element.

Imports System.Collections.Generic
Imports System.Linq

Public Module PER400_Violation
    Public Sub PrintStatus(accounts As IEnumerable(Of String))
        ' VIOLATION: Count() scans all items just to compare to zero.
        If accounts.Count() > 0 Then
            Console.WriteLine("Accounts found: " & accounts.Count().ToString())
        End If

        If accounts.LongCount() = 0 Then
            Console.WriteLine("No accounts.")
        End If
    End Sub
End Module
