' VIOLATION: OIM570 — MultiValueProperty modified (.Add) without writing .Value back via PutValue.
' The change to mvpRoles is accumulated in memory but never persisted to the database column.
Option Strict On
Imports VI.DB
Imports VI.DB.Entities

Public Module OIM570_Violation
    Public Sub AddRoleToAccount(ByVal entity As IEntity, ByVal newRole As String)
        Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)

        ' VIOLATION: .Add() modifies in-memory state only.
        ' Without entity.PutValue("Roles", mvpRoles.Value) the change is silently lost.
        mvpRoles.Add(newRole)

        ' Missing: entity.PutValue("Roles", mvpRoles.Value)
    End Sub
End Module
