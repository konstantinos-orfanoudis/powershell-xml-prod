' OIM580 compliant: VI_AE_ITDataFromOrg preceded by comment-based column dependency declarations.
' The '$Column$ comments tell the template engine to re-evaluate when those columns change.
Option Strict On

Public Module OIM580_Compliant
    Public Function GetCostCenter(ByVal UID_Person As String) As String
        ' Compliant: declare all hidden input columns as comment-based dependencies.
        '$Department$
        '$Location$
        '$FK(UID_Person).UID_ProfitCenter$
        Return VI_AE_ITDataFromOrg(UID_Person, "CostCenter")
    End Function
End Module
