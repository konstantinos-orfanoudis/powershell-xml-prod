Option Strict On
' PER452 compliant: Select() with only the columns actually needed.

Imports VI.DB

Public Module PER452_Compliant
    Public Sub ExportNames(Session As ISession)
        Dim q As New Query("Person")
        ' Compliant: only transfer the two columns the loop actually reads.
        q.Select("Firstname", "Lastname")
        q.CollectionLoadType = EntityCollectionLoadType.Slim

        Dim collection = Session.Source.GetCollection(q)
        For Each person In collection
            Console.WriteLine(person.GetValue("Firstname").String & " " &
                              person.GetValue("Lastname").String)
        Next
    End Sub
End Module
