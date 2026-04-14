Option Strict On
' OIM555 compliant: UnitOfWork batches all changes into a single transaction.
' One database round-trip for all N records instead of N round-trips.

Imports VI.DB

Public Module OIM555_Compliant
    Public Sub UpdateAccountFlags(Session As ISession, accountIds As String())
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        ' Compliant: start a UnitOfWork; accumulate changes; commit once.
        Using uow As IUnitOfWork = Session.StartUnitOfWork()
            For Each uid As String In accountIds
                Dim account = Session.Source.GetSingle(Of IEntity)(
                    "ADSAccount", f.UidComparison("UID_ADSAccount", uid))
                If account IsNot Nothing Then
                    account.PutValue("IsLocked", True)
                    uow.Put(account)   ' Stage the change — no DB call yet.
                End If
            Next
            uow.Commit()   ' Single round-trip for all staged changes.
        End Using
    End Sub
End Module
