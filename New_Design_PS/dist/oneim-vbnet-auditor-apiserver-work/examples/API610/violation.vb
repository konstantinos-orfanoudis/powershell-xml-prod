Option Strict On
' API610 violation: full exception detail enabled for the API surface.

Public Module API610_Violation
    Public Sub Configure(cfg As ServerLevelConfig)
        cfg.IncludeAllExceptionInfo = True
    End Sub
End Module
