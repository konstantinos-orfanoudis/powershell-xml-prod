Option Strict On
' API630 violation: wildcard CORS origin.

Public Module API630_Violation
    Public Sub Configure(cfg As ServerLevelConfig)
        cfg.CorsOrigins = New String() { "*" }
    End Sub
End Module
