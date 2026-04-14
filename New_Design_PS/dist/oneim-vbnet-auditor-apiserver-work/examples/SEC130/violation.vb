Option Strict On
' SEC130 violation: Obsolete HttpWebRequest API used.
' HttpWebRequest is marked SYSLIB0014 in .NET 6+ and lacks modern TLS/HTTP/2 support.

Imports System.Net
Imports System.IO

Public Module SEC130_Violation
    Public Function FetchData(url As String) As String
        ' VIOLATION: obsolete API.
        Dim request As HttpWebRequest = DirectCast(WebRequest.Create(url), HttpWebRequest)
        request.Method = "GET"
        Dim response As HttpWebResponse = DirectCast(request.GetResponse(), HttpWebResponse)
        Dim reader As New StreamReader(response.GetResponseStream())
        Return reader.ReadToEnd()
    End Function
End Module
