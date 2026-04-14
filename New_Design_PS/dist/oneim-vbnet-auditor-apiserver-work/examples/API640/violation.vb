Option Strict On
' API640 violation: forwarded header parsed manually.

Public Module API640_Violation
    Public Function ResolveIp(request As IRequest) As String
        Return request.Headers("X-Forwarded-For")
    End Function
End Module
