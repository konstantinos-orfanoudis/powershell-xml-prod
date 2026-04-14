Option Strict On
' REL220 compliant: Guard on trigger value before using it in PutValue.

Imports VI.DB
Imports VI.Base

Public Module REL220_Compliant
    Public Sub SyncDisplayName(entity As IEntity, Session As ISession)
        Dim tv = entity.GetTriggerValue("Firstname")
        If tv Is Nothing OrElse String.IsNullOrEmpty(tv.String) Then Return

        Dim firstName As String = tv.String
        Dim lastName As String = entity.GetValue("Lastname").String

        If Not String.IsNullOrEmpty(firstName) AndAlso Not String.IsNullOrEmpty(lastName) Then
            entity.PutValue("DisplayName", firstName & " " & lastName)
            entity.Save(Session)
        End If
    End Sub
End Module
