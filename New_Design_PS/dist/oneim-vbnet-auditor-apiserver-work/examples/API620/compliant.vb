Option Strict On
' API620 compliant: endpoint security permission checks remain enabled.

Public Module API620_Compliant
    Public Sub Configure(cfg As ServerLevelConfig)
        cfg.EnableEndpointSecurityPermissionCheck = True
    End Sub
End Module
