Option Strict On
' SEC140 compliant: Path resolved against a fixed base and checked for traversal.

Imports System
Imports System.IO

Public Module SEC140_Compliant
    Private Const BaseDir As String = "C:\SafeWorkDir\exports"

    Public Function ReadFile(fileName As String) As String
        Dim fullPath As String = Path.GetFullPath(Path.Combine(BaseDir, fileName))
        If Not fullPath.StartsWith(BaseDir, StringComparison.OrdinalIgnoreCase) Then
            Throw New UnauthorizedAccessException("Path traversal attempt detected.")
        End If
        Return File.ReadAllText(fullPath)
    End Function
End Module
