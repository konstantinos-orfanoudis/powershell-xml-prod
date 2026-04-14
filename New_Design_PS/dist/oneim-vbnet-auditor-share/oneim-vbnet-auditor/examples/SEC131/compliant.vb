Option Strict On
' SEC131 compliant: URL validated against a fixed allowlist before use.

Imports System
Imports System.Net.Http
Imports System.Threading.Tasks

Public Module SEC131_Compliant
    Private ReadOnly _httpClient As New HttpClient()
    Private ReadOnly _allowedHosts As String() = {"api.internal.example.com", "hooks.example.com"}

    Public Async Function CallService(url As String) As Task(Of String)
        Dim uri As New Uri(url)
        If Not Array.Exists(_allowedHosts, Function(h) h.Equals(uri.Host, StringComparison.OrdinalIgnoreCase)) Then
            Throw New InvalidOperationException("URL host is not in the allowed list: " & uri.Host)
        End If
        Dim response As HttpResponseMessage = Await _httpClient.GetAsync(uri)
        Return Await response.Content.ReadAsStringAsync()
    End Function
End Module
