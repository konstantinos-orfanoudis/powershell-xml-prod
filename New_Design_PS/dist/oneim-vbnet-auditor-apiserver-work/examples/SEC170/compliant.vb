Option Strict On
' SEC170 compliant: TLS 1.2 (minimum) and proper certificate validation.

Imports System.Net

Public Module SEC170_Compliant
    Public Sub ConfigureTransport()
        ' Compliant: require TLS 1.2 or 1.3 only.
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 Or SecurityProtocolType.Tls13
        ' No ServerCertificateValidationCallback override — let the OS chain validate normally.
    End Sub
End Module
