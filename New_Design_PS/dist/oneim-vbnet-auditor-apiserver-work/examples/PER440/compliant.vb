Option Strict On
' PER440 compliant: Regex instance created once, outside the loop.

Imports System.Text.RegularExpressions
Imports System.Collections.Generic

Public Module PER440_Compliant
    ' Compliant: compiled Regex created once at module level.
    Private ReadOnly _namePattern As New Regex("^[A-Z][a-z]+$", RegexOptions.Compiled)

    Public Sub ProcessNames(names As IEnumerable(Of String))
        For Each name As String In names
            If _namePattern.IsMatch(name) Then
                Console.WriteLine("Valid: " & name)
            End If
        Next
    End Sub
End Module
