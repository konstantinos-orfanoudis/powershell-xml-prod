Option Explicit On
Option Strict On

' VIOLATION: OIM590 — GetList called with an empty WHERE filter, loading the entire table.
Public Function GetAllAccounts(session As ISession) As IEntity()
    ' VIOLATION: OIM590 — empty string returns every row in PersonHasAccount.
    ' In production this can mean tens of millions of rows loaded into memory.
    Dim allAccounts As IEntity() = session.Source.GetList(Of IEntity)("PersonHasAccount", "")
    Return allAccounts
End Function

Public Sub ProcessEverything(session As ISession)
    ' VIOLATION: OIM590 — String.Empty is treated the same as an empty filter.
    Dim all As IEntity() = session.Source.GetList(Of IEntity)("ADSAccount", String.Empty)
    For Each e As IEntity In all
        e.SetValue("IsEnabled", False)
    Next
End Sub
