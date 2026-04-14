' VB001 violation: Option Explicit is NOT declared
' Without Option Explicit, undeclared variables are silently created as Object.

Imports System

Public Module VB001_Violation
    Public Sub Run()
        ' No 'Option Explicit On' at the top of this file.
        ' The variable 'userName' is used but never declared.
        userName = "Alice"
        Console.WriteLine(userName)
    End Sub
End Module
