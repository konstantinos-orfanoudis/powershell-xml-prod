Option Strict On
' PER420 violation: Same IEnumerable enumerated multiple times.
' If the source is lazy (e.g. LINQ query), each Count() re-runs the query.

Imports System.Collections.Generic
Imports System.Linq

Public Module PER420_Violation
    Public Sub Report(accounts As IEnumerable(Of String))
        ' VIOLATION: accounts may be a lazy LINQ sequence; each Count() re-evaluates it.
        If accounts.Count() > 0 Then
            Console.WriteLine("Total: " & accounts.Count().ToString())
            Console.WriteLine("Long: " & accounts.LongCount().ToString())
        End If
    End Sub
End Module
