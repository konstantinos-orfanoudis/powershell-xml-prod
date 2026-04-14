Option Explicit On
Option Strict On

' COMPLIANT: OIM590 — GetList always has a specific WHERE clause to limit the result set.
Public Function GetAccountsForPerson(session As ISession, uidPerson As String) As IEntity()
    Dim whereClause As String = String.Format("UID_Person = '{0}'", uidPerson)
    Dim accounts As IEntity() = session.Source.GetList(Of IEntity)("PersonHasAccount", whereClause)
    Return accounts
End Function

Public Sub DeactivateOrphanedAccounts(session As ISession)
    ' Specific WHERE clause limits the result to orphaned accounts only.
    Dim where As String = "IsOrphaned = 1 AND IsEnabled = 1"
    Dim orphaned As IEntity() = session.Source.GetList(Of IEntity)("ADSAccount", where)
    For Each e As IEntity In orphaned
        e.SetValue("IsEnabled", False)
    Next
End Sub
