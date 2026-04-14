Option Explicit On
Option Strict On

' COMPLIANT: VB006 — TryParse used; invalid input handled gracefully.
Public Function GetEmployeeNumber(entity As IEntity) As Integer
    Dim raw As String = CStr(entity.GetValue("EmployeeNumber"))
    Dim result As Integer = 0
    If Integer.TryParse(raw, result) Then
        Return result
    End If
    ' Return a safe default when the value cannot be parsed.
    Return 0
End Function

Public Function GetSalary(entity As IEntity) As Double
    Dim rawSalary As String = CStr(entity.GetValue("Salary"))
    Dim result As Double = 0.0
    If Double.TryParse(rawSalary, result) Then
        Return result
    End If
    Return 0.0
End Function
