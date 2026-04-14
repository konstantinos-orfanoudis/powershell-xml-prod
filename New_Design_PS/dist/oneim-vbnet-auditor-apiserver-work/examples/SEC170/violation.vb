Option Strict On
' SEC170 violation: Deprecated SSL3/TLS1.0 protocol and certificate validation disabled.

Imports System.Net
Imports System.Net.Security
Imports System.Security.Cryptography.X509Certificates

Public Module SEC170_Violation
    Public Sub ConfigureTransport()
        ' VIOLATION: SSL3 is broken; TLS 1.0 is deprecated.
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Ssl3 Or SecurityProtocolType.Tls

        ' VIOLATION: disables ALL certificate validation — MITM attacks succeed silently.
        ServicePointManager.ServerCertificateValidationCallback =
            Function(s, cert, chain, errors) True
    End Sub
End Module
