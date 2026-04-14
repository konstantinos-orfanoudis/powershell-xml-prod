' VB002 violation: Option Strict is NOT declared.
' Without Option Strict, implicit narrowing conversions and late binding are allowed.

Imports System

Public Module VB002_Violation
    Public Sub Run()
        ' Implicit conversion from Double to Integer — silently truncates.
        Dim count As Integer = 3.9
        ' Late-bound call — resolved at runtime, no compile-time checking.
        Dim obj As Object = "hello"
        obj.ToUpper()
        Console.WriteLine(count)
    End Sub
End Module
