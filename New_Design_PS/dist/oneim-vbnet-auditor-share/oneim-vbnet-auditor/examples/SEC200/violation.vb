Option Explicit On
Option Strict On

Imports System.Diagnostics

' VIOLATION: SEC200 — Process.Start() called with a value derived from provisioning data.
Public Sub ExportPersonData(entity As IEntity)
    Dim exportPath As String = CStr(entity.GetValue("ExportPath"))
    ' VIOLATION: SEC200 — if ExportPath contains malicious data (e.g. "; rm -rf /"),
    ' arbitrary OS commands can be injected through the argument.
    Process.Start("export-tool.exe", exportPath)
End Sub

Public Sub NotifyExternal(uid As String)
    ' VIOLATION: SEC200 — Process.Start with a hardcoded executable is still flagged
    ' because arguments may be tainted.
    Process.Start("C:\Tools\notifier.exe", uid)
End Sub
