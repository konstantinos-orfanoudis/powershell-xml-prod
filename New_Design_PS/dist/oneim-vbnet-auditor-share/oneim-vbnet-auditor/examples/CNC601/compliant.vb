Option Strict On
' CNC601 compliant: BeginTransaction always paired with Commit inside Try, Rollback in Catch.

Imports VI.DB

Public Module CNC601_Compliant
    Public Sub UpdateRecord(Session As ISession, uid As String)
        Session.BeginTransaction()
        Try
            Dim entity = Session.Source.GetSingle(Of IEntity)("Person",
                Session.Resolve(Of ISqlFormatter)().UidComparison("UID_Person", uid))
            entity.PutValue("IsLocked", True)
            entity.Save(Session)
            Session.CommitTransaction()
        Catch
            Session.RollbackTransaction()
            Throw
        End Try
    End Sub
End Module
