Option Strict On
' API640 compliant: framework helper resolves the request IP.

Public Module API640_Compliant
    Public Function ResolveIp(request As IRequest) As String
        Return request.GetRequestIpAddress()
    End Function
End Module
