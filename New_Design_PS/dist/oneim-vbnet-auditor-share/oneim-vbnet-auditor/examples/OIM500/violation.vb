Option Strict On
' OIM500 violation: PutValue called without a sync-time guard (no FULLSYNC / change check).
' This may cause unintended side-effects on every provisioning call.

Imports VI.DB

Public Module OIM500_Violation
    Public Sub SetDerivedField(entity As IEntity, Session As ISession)
        ' VIOLATION: PutValue runs unconditionally — no IsModified, IsFullSync, or
        ' state-based guard to restrict when this write should happen.
        entity.PutValue("DerivedField", "computed-value")
        entity.Save(Session)
    End Sub
End Module
