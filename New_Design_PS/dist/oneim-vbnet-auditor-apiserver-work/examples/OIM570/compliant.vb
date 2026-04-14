' OIM570 compliant: MultiValueProperty change is written back via PutValue.
Option Strict On
Imports VI.DB
Imports VI.DB.Entities

Public Module OIM570_Compliant
    Public Sub AddRoleToAccount(ByVal entity As IEntity, ByVal newRole As String)
        Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)

        If Not mvpRoles.Contains(newRole) Then
            mvpRoles.Add(newRole)
        End If

        ' Compliant: write the updated value back so the change is persisted.
        entity.PutValue("Roles", mvpRoles.Value)
    End Sub
End Module
