Option Strict On
' CNC601 violation: BeginTransaction without a visible Commit or Rollback in scope.
' If the method exits or throws, the transaction is left open, holding locks.

Imports VI.DB

Public Module CNC601_Violation
    Public Sub UpdateRecord(Session As ISession, uid As String)
        Session.BeginTransaction()
        ' VIOLATION: no Commit or Rollback visible in the next ~60 lines.
        Dim entity = Session.Source.GetSingle(Of IEntity)("Person",
            Session.Resolve(Of ISqlFormatter)().UidComparison("UID_Person", uid))
        entity.PutValue("IsLocked", True)
        entity.Save(Session)
        ' Missing: Session.CommitTransaction()
    End Sub
End Module
