Option Strict On
' REL250 violation: Disposable resource declared with Dim — may leak on exception.
' If an exception occurs between Dim and the manual .Close() call, the handle leaks.

Imports System.IO
Imports System.Net

Public Module REL250_Violation
    Public Function ReadFileContent(path As String) As String
        ' VIOLATION: StreamReader created with Dim — not in a Using block.
        Dim reader As New StreamReader(path)
        Dim content As String = reader.ReadToEnd()
        reader.Close()   ' Not called if ReadToEnd throws.
        Return content
    End Function

    Public Function FetchResponse(url As String) As String
        Dim request As HttpWebRequest = DirectCast(WebRequest.Create(url), HttpWebRequest)
        ' VIOLATION: HttpWebResponse created with Dim — not in a Using block.
        Dim response As New System.Net.HttpWebResponse()
        Dim reader As New StreamReader(response.GetResponseStream())
        Return reader.ReadToEnd()
    End Function
End Module
