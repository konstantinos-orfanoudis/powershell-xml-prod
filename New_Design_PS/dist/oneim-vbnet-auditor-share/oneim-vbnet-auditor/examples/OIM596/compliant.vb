Option Explicit On
Option Strict On

' COMPLIANT: OIM596 — Business values read from Designer Configuration Parameters via
' Connection.GetConfigParmValue. Administrators can update the values without touching code.
Public Function IsHREmployee(entity As IEntity) As Boolean
    Dim dept As String = CStr(entity.GetValue("Department"))
    ' Configuration Parameter "Custom\HRDepartmentCode" is defined in Designer and
    ' returns the environment-specific value (e.g. "HR", "Human Resources", "HR-DE").
    Dim hrCode As String = CStr(Connection.GetConfigParmValue("Custom\HRDepartmentCode"))
    Return dept = hrCode
End Function

Public Function GetDefaultLocation(entity As IEntity) As String
    Dim location As String = CStr(entity.GetValue("PrimaryLocation"))
    Dim germanyLocations As String = CStr(Connection.GetConfigParmValue("Custom\GermanyLocations"))
    ' germanyLocations is a pipe-separated list: "Berlin|Hamburg|Munich"
    Dim locations As String() = germanyLocations.Split("|"c)
    If Array.IndexOf(locations, location) >= 0 Then
        Return "Germany"
    End If
    Return "Other"
End Function
