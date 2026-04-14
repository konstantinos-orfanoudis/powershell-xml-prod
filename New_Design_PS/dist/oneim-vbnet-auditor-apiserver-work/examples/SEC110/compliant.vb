Option Strict On
' SEC110 compliant: No external process launched.
' Use native OneIM APIs or .NET APIs to perform the same work.

Imports System.IO
Imports VI.DB

Public Module SEC110_Compliant
    Public Sub RunCleanup(Session As ISession, targetFolder As String)
        ' Compliant: use .NET IO APIs with a validated fixed base path.
        Dim basePath As String = "C:\SafeWorkDir\cleanup"
        Dim safePath As String = IO.Path.GetFullPath(IO.Path.Combine(basePath, "output.log"))
        If safePath.StartsWith(basePath, StringComparison.OrdinalIgnoreCase) Then
            IO.File.WriteAllText(safePath, "cleanup complete")
        End If
    End Sub
End Module
