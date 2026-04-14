Option Explicit On
' VB003 violation: Late binding and Object-heavy code.
' CreateObject, CallByName, and As Object lose type safety.

Imports System

Public Module VB003_Violation
    Public Sub Run()
        ' Late-bound COM object — no compile-time checking.
        Dim app As Object = CreateObject("Excel.Application")
        app.Visible = True

        ' As Object receives anything — weakens type checking.
        Dim result As Object = GetData()
        Console.WriteLine(result.Length)   ' Resolved at runtime.
    End Sub

    Private Function GetData() As Object
        Return "some string"
    End Function
End Module
