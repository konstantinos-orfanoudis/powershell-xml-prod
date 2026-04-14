Option Strict On
' PER430 violation: Session/database access repeated inside a loop.
' Each call inside the loop triggers a database round-trip.

Imports VI.DB

Public Module PER430_Violation
    Public Sub ProcessAccounts(Session As ISession, accountIds As String())
        For Each uid As String In accountIds
            ' VIOLATION: Session.Source inside a loop — one round-trip per account.
            Dim dept As String = CStr(Session.Source.GetSingleValue("Department", "Name",
                Session.Resolve(Of ISqlFormatter)().UidComparison("UID_Person", uid)))
            Console.WriteLine(uid & " -> " & dept)
        Next
    End Sub
End Module
