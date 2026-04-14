Option Strict On
' CNC602 compliant: Only one BeginTransaction per logical unit of work.

Imports VI.DB

Public Module CNC602_Compliant
    Public Sub SingleBegin(Session As ISession)
        Session.BeginTransaction()
        Try
            ' ... all work in a single transaction scope ...
            Session.CommitTransaction()
        Catch
            Session.RollbackTransaction()
            Throw
        End Try
    End Sub
End Module
