Option Strict On
' VB003 compliant: Strongly-typed references only.

Imports System

Public Module VB003_Compliant
    Public Sub Run()
        ' Strongly typed — compile-time checking available.
        Dim result As String = GetData()
        Console.WriteLine(result.Length)
    End Sub

    Private Function GetData() As String
        Return "some string"
    End Function
End Module
