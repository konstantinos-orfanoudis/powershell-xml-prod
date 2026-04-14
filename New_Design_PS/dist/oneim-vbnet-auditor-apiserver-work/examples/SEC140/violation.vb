Option Strict On
' SEC140 violation: File I/O with a variable-driven path — path traversal risk.
' If filePath contains ".." or an absolute path, arbitrary files can be read.

Imports System.IO

Public Module SEC140_Violation
    Public Function ReadFile(filePath As String) As String
        ' VIOLATION: no base-path check; user can supply "../../secret.txt".
        Return File.ReadAllText(filePath)
    End Function
End Module
