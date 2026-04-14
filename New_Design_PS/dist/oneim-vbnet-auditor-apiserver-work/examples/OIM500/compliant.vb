Option Strict On
' OIM500 compliant: PutValue guarded by a sync-time state check.

Imports VI.DB

Public Module OIM500_Compliant
    Public Sub SetDerivedField(entity As IEntity, Session As ISession)
        ' Compliant: only write when the relevant source field was actually changed.
        If entity.IsModified("SourceField") Then
            entity.PutValue("DerivedField", "computed-value")
            entity.Save(Session)
        End If
    End Sub
End Module
