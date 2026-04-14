' OIM571 compliant: MultiValueProperty index access guarded by a .Count check.
Option Strict On
Imports VI.DB
Imports VI.DB.Entities

Public Module OIM571_Compliant
    Public Function GetPrimaryRole(ByVal entity As IEntity) As String
        Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)

        ' Compliant: check .Count before accessing by index.
        If mvpRoles.Count > 0 Then
            Return mvpRoles(0)
        End If

        Return String.Empty
    End Function
End Module
