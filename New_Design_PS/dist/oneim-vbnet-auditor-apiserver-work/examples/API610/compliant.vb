Option Strict On
' API610 compliant: full exception detail stays disabled by default.

Public Module API610_Compliant
    Public Sub Configure(cfg As ServerLevelConfig)
        cfg.IncludeAllExceptionInfo = False
    End Sub
End Module
