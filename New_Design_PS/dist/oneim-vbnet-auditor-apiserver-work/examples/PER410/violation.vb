Option Strict On
' PER410 violation: String concatenation with & inside a loop.
' Each iteration allocates a new String object — O(n^2) allocations for n items.

Imports System.Collections.Generic

Public Module PER410_Violation
    Public Function BuildCsvList(items As IEnumerable(Of String)) As String
        Dim result As String = ""
        For Each item As String In items
            ' VIOLATION: new String allocated on every iteration.
            result = result & item & ","
        Next
        Return result.TrimEnd(","c)
    End Function
End Module
