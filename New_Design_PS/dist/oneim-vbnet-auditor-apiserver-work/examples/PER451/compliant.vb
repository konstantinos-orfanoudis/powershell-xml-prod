Option Strict On
' PER451 compliant: Pre-select all needed columns so no .Create(Session) is needed in the loop.

Imports VI.DB

Public Module PER451_Compliant
    Public Sub ProcessPersonAccounts(Session As ISession)
        ' Compliant: select exactly the columns needed upfront; no per-row Create() calls.
        Dim q As New Query("Person")
        q.Select("UID_Person", "Firstname", "Lastname")
        q.CollectionLoadType = EntityCollectionLoadType.Slim

        Dim collection = Session.Source.GetCollection(q)
        For Each entry In collection
            ' All selected columns already loaded — no extra round-trip.
            Console.WriteLine(entry.GetValue("Firstname").String)
        Next
    End Sub
End Module
