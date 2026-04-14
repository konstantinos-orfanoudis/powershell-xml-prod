Option Strict On
' SEC110 violation: External process launched from OneIM script logic.
' An attacker who controls scriptParam can run arbitrary commands.

Imports System.Diagnostics

Public Module SEC110_Violation
    Public Sub RunCleanup(scriptParam As String)
        ' VIOLATION: user-supplied input passed to a shell command.
        Process.Start("cmd.exe", "/c cleanup.bat " & scriptParam)
    End Sub
End Module
