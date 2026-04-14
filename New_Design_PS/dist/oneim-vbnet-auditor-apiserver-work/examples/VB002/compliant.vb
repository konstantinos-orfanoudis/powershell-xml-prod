Option Strict On
' VB002 compliant: Option Strict On is declared.
' No implicit narrowing conversions; all types must be explicitly declared.

Imports System

Public Module VB002_Compliant
    Public Sub Run()
        Dim count As Integer = CInt(3.9)   ' Explicit conversion — intent is clear.
        Dim text As String = "hello"
        Console.WriteLine(text.ToUpper())
        Console.WriteLine(count)
    End Sub
End Module
