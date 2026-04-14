Option Strict On
' OIM555 violation: IEntity.Save(Session) called inside a loop.
' Each Save() is an individual INSERT/UPDATE round-trip — N database calls for N records.

Imports VI.DB

Public Module OIM555_Violation
    Public Sub UpdateAccountFlags(Session As ISession, accountIds As String())
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        For Each uid As String In accountIds
            Dim account = Session.Source.GetSingle(Of IEntity)(
                "ADSAccount", f.UidComparison("UID_ADSAccount", uid))
            If account IsNot Nothing Then
                account.PutValue("IsLocked", True)
                ' VIOLATION: Save(Session) inside loop — one round-trip per account.
                account.Save(Session)
            End If
        Next
    End Sub
End Module
