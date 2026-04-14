Option Strict On
' WEB600 compliant: System.Net.Http.HttpClient used instead of obsolete APIs.

Imports System.Net.Http
Imports System.Threading.Tasks

Public Module WEB600_Compliant
    ' Single shared instance — HttpClient is designed to be reused.
    Private ReadOnly _http As New HttpClient()

    Public Async Function CallRestApiAsync(url As String) As Task(Of String)
        Dim response As HttpResponseMessage = Await _http.GetAsync(url)
        response.EnsureSuccessStatusCode()
        Return Await response.Content.ReadAsStringAsync()
    End Function
End Module
