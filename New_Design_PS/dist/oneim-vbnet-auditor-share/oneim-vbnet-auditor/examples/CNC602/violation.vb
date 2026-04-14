Option Strict On
' CNC602 violation: BeginTransaction called twice before a Commit — nested transaction.
' Most ADO.NET providers do not support true nested transactions.

Imports VI.DB

Public Module CNC602_Violation
    Public Sub DoubleBegin(Session As ISession)
        Session.BeginTransaction()
        ' ... some work ...
        Session.BeginTransaction()   ' VIOLATION: second Begin before Commit/Rollback.
        ' ... more work ...
        Session.CommitTransaction()
    End Sub
End Module
