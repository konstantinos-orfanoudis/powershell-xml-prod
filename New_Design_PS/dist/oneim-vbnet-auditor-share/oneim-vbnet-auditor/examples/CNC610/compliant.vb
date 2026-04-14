Option Strict On
' CNC610 compliant: Template writes a field without creating a circular dependency.
' DisplayName reads only base fields (Firstname, Lastname) that it does not write.

Imports VI.DB

Public Module CNC610_Compliant
    ' Compliant: DisplayName reads only source fields it does not write.
    ' No cycle: DisplayName -> Firstname, Lastname (neither depends on DisplayName).
    Public Sub BuildDisplayName(entity As IEntity, Session As ISession)
        Dim firstName As String = entity.GetValue("Firstname").String
        Dim lastName As String = entity.GetValue("Lastname").String
        entity.PutValue("DisplayName", firstName & " " & lastName)
        entity.Save(Session)
    End Sub
End Module
