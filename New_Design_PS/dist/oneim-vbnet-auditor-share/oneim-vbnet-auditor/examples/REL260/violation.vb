Option Explicit On
Option Strict On

' VIOLATION: REL260 — CType/DirectCast used without a preceding TypeOf ... Is guard.
Public Function GetDepartmentEntity(obj As Object) As IDepartmentEntity
    ' No TypeOf check before the cast; throws InvalidCastException if obj is Nothing
    ' or a different runtime type.
    Dim dept As IDepartmentEntity = CType(obj, IDepartmentEntity)
    Return dept
End Function

Public Sub ProcessRole(roleObj As Object)
    ' VIOLATION: REL260 — DirectCast without TypeOf guard
    Dim role As IRoleEntity = DirectCast(roleObj, IRoleEntity)
    role.SetValue("IsActive", True)
End Sub
