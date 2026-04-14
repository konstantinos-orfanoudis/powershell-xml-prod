Option Strict On
' API620 violation: endpoint security permission checks disabled.

Public Module API620_Violation
    Public Sub Configure(cfg As ServerLevelConfig)
        cfg.EnableEndpointSecurityPermissionCheck = False
    End Sub
End Module
