Option Explicit On
Option Strict On

' COMPLIANT: REL260 — TypeOf ... Is guard precedes every CType/DirectCast.
Public Function GetDepartmentEntity(obj As Object) As IDepartmentEntity
    If TypeOf obj Is IDepartmentEntity Then
        Dim dept As IDepartmentEntity = CType(obj, IDepartmentEntity)
        Return dept
    End If
    Return Nothing
End Function

Public Sub ProcessRole(roleObj As Object)
    ' TryCast returns Nothing instead of throwing; IsNot Nothing guard handles the failure case.
    Dim role As IRoleEntity = TryCast(roleObj, IRoleEntity)
    If role IsNot Nothing Then
        role.SetValue("IsActive", True)
    End If
End Sub
