Option Strict On
' REL220 violation: PutValue driven by GetTriggerValue without a Nothing/empty guard.
' If the trigger field is absent, the value written may be Nothing or empty.

Imports VI.DB
Imports VI.Base

Public Module REL220_Violation
    Public Sub SyncDisplayName(entity As IEntity, Session As ISession)
        ' VIOLATION: GetTriggerValue result used in PutValue without Nothing check.
        Dim firstName As String = entity.GetTriggerValue("Firstname").String
        Dim lastName As String = entity.GetTriggerValue("Lastname").String
        entity.PutValue("DisplayName", firstName & " " & lastName)
        entity.Save(Session)
    End Sub
End Module
