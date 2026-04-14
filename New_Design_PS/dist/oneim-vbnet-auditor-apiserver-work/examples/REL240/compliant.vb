Option Strict On
' REL240 compliant: IsEmpty checked before accessing FK parent properties.

Imports VI.DB

Public Module REL240_Compliant
    Public Sub PrintDepartmentName(person As IEntity, Session As ISession)
        Dim fk = person.GetFk("UID_Department")
        If fk.IsEmpty Then
            Console.WriteLine("Department: (none assigned)")
            Return
        End If
        Dim dept As IEntity = fk.GetParent(Session)
        Console.WriteLine("Department: " & dept.GetValue("DeptName").String)
    End Sub
End Module
