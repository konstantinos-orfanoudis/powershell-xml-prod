' VIOLATION: OIM571 — MultiValueProperty accessed by index without a preceding .Count bounds check.
' If the MVP has fewer items than expected, mvpRoles(0) throws IndexOutOfRangeException.
Option Strict On
Imports VI.DB
Imports VI.DB.Entities

Public Module OIM571_Violation
    Public Function GetPrimaryRole(ByVal entity As IEntity) As String
        Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)

        ' VIOLATION: direct index access with no .Count guard.
        ' Throws IndexOutOfRangeException when Roles column is empty.
        Return mvpRoles(0)
    End Function
End Module
