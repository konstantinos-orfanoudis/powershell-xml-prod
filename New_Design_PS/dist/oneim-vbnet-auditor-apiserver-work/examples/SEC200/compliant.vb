Option Explicit On
Option Strict On

' COMPLIANT: SEC200 — No Process.Start() calls. External communication is done via
' OneIM's built-in notification framework or a dedicated connector, not OS processes.
Public Sub NotifyExternal(entity As IEntity)
    ' Use OneIM notification API instead of launching a process.
    Dim mailAddress As String = CStr(entity.GetValue("DefaultEmailAddress"))
    If Not String.IsNullOrWhiteSpace(mailAddress) Then
        Session.Source.Notify(mailAddress, "Provisioning completed.")
    End If
End Sub

Public Function BuildExportPayload(entity As IEntity) As String
    ' Data is serialized and handed to a connector; no OS process is spawned.
    Return String.Format("uid={0};name={1}", _
        entity.GetValue("UID_Person"), _
        entity.GetValue("CentralAccount"))
End Function
