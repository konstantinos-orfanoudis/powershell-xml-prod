Option Strict On
' WEB600 violation: Obsolete HttpWebRequest / WebClient APIs used.
' HttpWebRequest is SYSLIB0014 in .NET 6+; lacks HTTP/2 and modern TLS handling.

Imports System.Net
Imports System.IO

Public Module WEB600_Violation
    Public Function CallRestApi(url As String) As String
        ' VIOLATION: HttpWebRequest.Create() — obsolete.
        Dim request As HttpWebRequest = DirectCast(HttpWebRequest.Create(url), HttpWebRequest)
        request.Method = "GET"
        Using response As HttpWebResponse = DirectCast(request.GetResponse(), HttpWebResponse)
            Using reader As New StreamReader(response.GetResponseStream())
                Return reader.ReadToEnd()
            End Using
        End Using
    End Function

    Public Function DownloadString(url As String) As String
        ' VIOLATION: New WebClient() — also obsolete.
        Dim client As New WebClient()
        Return client.DownloadString(url)
    End Function
End Module
