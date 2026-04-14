Option Strict On
' REL250 compliant: Disposable resources wrapped in Using blocks.
' Dispose() is guaranteed even when an exception occurs.

Imports System.IO

Public Module REL250_Compliant
    Public Function ReadFileContent(path As String) As String
        ' Compliant: StreamReader in a Using block — Dispose() always called.
        Using reader As New StreamReader(path)
            Return reader.ReadToEnd()
        End Using
    End Function
End Module
