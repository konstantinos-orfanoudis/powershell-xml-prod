Option Strict On
' SEC130 compliant: Use System.Net.Http.HttpClient instead of obsolete APIs.

Imports System.Net.Http
Imports System.Threading.Tasks

Public Module SEC130_Compliant
    ' Share a single HttpClient instance across calls.
    Private ReadOnly _httpClient As New HttpClient()

    Public Async Function FetchDataAsync(url As String) As Task(Of String)
        ' Compliant: modern HttpClient with async support and HTTP/2.
        Dim response As HttpResponseMessage = Await _httpClient.GetAsync(url)
        response.EnsureSuccessStatusCode()
        Return Await response.Content.ReadAsStringAsync()
    End Function
End Module
