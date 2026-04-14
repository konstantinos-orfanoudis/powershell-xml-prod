Option Strict On
' PER420 compliant: Materialise the sequence once with ToList() before multiple passes.

Imports System.Collections.Generic
Imports System.Linq

Public Module PER420_Compliant
    Public Sub Report(accounts As IEnumerable(Of String))
        Dim list As List(Of String) = accounts.ToList()
        If list.Count > 0 Then
            Console.WriteLine("Total: " & list.Count.ToString())
        End If
    End Sub
End Module
