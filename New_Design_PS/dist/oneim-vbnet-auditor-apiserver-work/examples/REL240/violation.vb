Option Strict On
' REL240 violation: GetFk() result used directly without IsEmpty check.
' If the FK row does not exist, GetParent() or GetValue() throws or returns empty object.

Imports VI.DB

Public Module REL240_Violation
    Public Sub PrintDepartmentName(person As IEntity, Session As ISession)
        ' VIOLATION: no IsEmpty check — NullReferenceException if FK row is absent.
        Dim deptName As String = person.GetFk("UID_Department").GetParent(Session).GetValue("DeptName").String
        Console.WriteLine("Department: " & deptName)
    End Sub
End Module
