' VIOLATION: OIM580 — VI_AE_ITDataFromOrg called without comment-based column dependency declarations.
' The template engine cannot see the hidden input columns (Department, Location, CostCenter) and
' will not re-evaluate this template when those values change.
Option Strict On

Public Module OIM580_Violation
    Public Function GetCostCenter(ByVal UID_Person As String) As String
        ' VIOLATION: no '$Column$ dependency comment lines before this call.
        ' The template engine is unaware of Department, Location, and UID_ProfitCenter.
        Return VI_AE_ITDataFromOrg(UID_Person, "CostCenter")
    End Function
End Module
