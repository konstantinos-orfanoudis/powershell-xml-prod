Option Explicit On
Option Strict On

' VIOLATION: OIM596 — Business values hardcoded as string literals instead of using
' Connection.GetConfigParmValue. When "HR" or "Berlin" changes, the script must be
' edited and redeployed.
Public Function IsHREmployee(entity As IEntity) As Boolean
    Dim dept As String = CStr(entity.GetValue("Department"))
    ' VIOLATION: OIM596 — "HR" is a business value that may vary by environment or
    ' change over time. It should be stored as a Configuration Parameter in Designer.
    Return dept = "HR"
End Function

Public Function GetDefaultLocation(entity As IEntity) As String
    Dim location As String = CStr(entity.GetValue("PrimaryLocation"))
    If location = "Berlin" OrElse location = "Hamburg" Then
        Return "Germany"
    End If
    Return "Other"
End Function
