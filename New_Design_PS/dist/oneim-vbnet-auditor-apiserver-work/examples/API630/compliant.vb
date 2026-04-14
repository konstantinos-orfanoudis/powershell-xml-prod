Option Strict On
' API630 compliant: explicit trusted origin list.

Public Module API630_Compliant
    Public Sub Configure(cfg As ServerLevelConfig)
        cfg.CorsOrigins = New String() { "https://portal.example.com" }
    End Sub
End Module
