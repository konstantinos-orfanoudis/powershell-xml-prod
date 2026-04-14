Option Strict On
' PER451 violation: .Create(Session) called inside a loop — N+1 SELECT pattern.
' Each Create() inflates a slim collection entry with an additional database round-trip.

Imports VI.DB

Public Module PER451_Violation
    Public Sub ProcessPersonAccounts(collection As IEntityCollection, Session As ISession)
        For Each entry In collection
            ' VIOLATION: .Create(Session) inside loop — one extra SELECT per row.
            Dim person As IEntity = entry.Create(Session)
            Console.WriteLine(person.GetValue("Firstname").String)
        Next
    End Sub
End Module
