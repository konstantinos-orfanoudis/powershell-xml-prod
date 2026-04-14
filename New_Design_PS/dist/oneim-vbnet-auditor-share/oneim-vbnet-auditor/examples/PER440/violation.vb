Option Strict On
' PER440 violation: Heavy object allocated inside a loop body.
' A new RegEx or XmlDocument created per iteration increases GC pressure.

Imports System.Text.RegularExpressions
Imports System.Collections.Generic

Public Module PER440_Violation
    Public Sub ProcessNames(names As IEnumerable(Of String))
        For Each name As String In names
            ' VIOLATION: Regex compiled on every iteration — expensive allocation.
            Dim regex As New Regex("^[A-Z][a-z]+$", RegexOptions.Compiled)
            If regex.IsMatch(name) Then
                Console.WriteLine("Valid: " & name)
            End If
        Next
    End Sub
End Module
