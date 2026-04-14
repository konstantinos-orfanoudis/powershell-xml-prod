Option Explicit On
Option Strict On

' VIOLATION: VB006 — Integer.Parse() used without TryParse; throws FormatException on invalid input.
Public Function GetEmployeeNumber(entity As IEntity) As Integer
    Dim raw As String = CStr(entity.GetValue("EmployeeNumber"))
    ' If raw is empty, null, or non-numeric this line throws FormatException.
    Dim result As Integer = Integer.Parse(raw)
    Return result
End Function

Public Function GetSalary(entity As IEntity) As Double
    Dim rawSalary As String = CStr(entity.GetValue("Salary"))
    ' VIOLATION: VB006
    Return Double.Parse(rawSalary)
End Function
