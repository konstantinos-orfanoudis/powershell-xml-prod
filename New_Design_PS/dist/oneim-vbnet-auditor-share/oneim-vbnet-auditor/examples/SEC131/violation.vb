Option Strict On
' SEC131 violation: Outbound HTTP request with a variable-driven URL.
' If the url variable comes from user input or config, SSRF is possible.

Imports System.Net.Http
Imports System.Threading.Tasks

Public Module SEC131_Violation
    Private ReadOnly _httpClient As New HttpClient()

    Public Async Function CallService(url As String) As Task(Of String)
        ' VIOLATION: URL is not validated against an allowlist.
        Dim response As HttpResponseMessage = Await _httpClient.GetAsync(url)
        Return Await response.Content.ReadAsStringAsync()
    End Function
End Module
