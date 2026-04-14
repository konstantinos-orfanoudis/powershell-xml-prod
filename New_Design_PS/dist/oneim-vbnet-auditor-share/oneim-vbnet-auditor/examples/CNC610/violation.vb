Option Strict On
' CNC610 violation: Template that writes values participates in a circular dependency.
' Template A calls Template B which calls Template A — cascading re-evaluations.
' (This rule is flagged by the cascade graph analyser, not by source code pattern alone.)

Imports VI.DB

Public Module CNC610_Violation
    ' This template (e.g. Person.DisplayName) writes a field AND reads a field
    ' that is itself computed by another template which reads DisplayName.
    ' The cycle: DisplayName -> FullTitle -> DisplayName
    Public Sub BuildDisplayName(entity As IEntity, Session As ISession)
        ' Reads FullTitle (which depends on DisplayName — creates a write cycle).
        Dim title As String = entity.GetValue("FullTitle").String
        ' Writes DisplayName — this template is a writer in the cycle.
        entity.PutValue("DisplayName", title & " " & entity.GetValue("Lastname").String)
        entity.Save(Session)
    End Sub
End Module
