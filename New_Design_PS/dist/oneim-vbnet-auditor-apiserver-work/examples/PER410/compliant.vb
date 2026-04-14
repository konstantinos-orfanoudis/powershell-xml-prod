Option Strict On
' PER410 compliant: StringBuilder used for accumulation inside a loop.

Imports System.Collections.Generic
Imports System.Text

Public Module PER410_Compliant
    Public Function BuildCsvList(items As IEnumerable(Of String)) As String
        Dim sb As New StringBuilder()
        For Each item As String In items
            If sb.Length > 0 Then sb.Append(","c)
            sb.Append(item)
        Next
        Return sb.ToString()
    End Function
End Module
