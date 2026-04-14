Option Strict On
' PER452 violation: .SelectAll() loads every column — huge network payload for wide tables.
' For a 60-column Person table, each row transfers all columns even if only 2 are needed.

Imports VI.DB

Public Module PER452_Violation
    Public Sub ExportNames(Session As ISession)
        Dim q As New Query("Person")
        ' VIOLATION: SelectAll() retrieves all 60+ Person columns.
        q.SelectAll()

        Dim collection = Session.Source.GetCollection(q)
        For Each person In collection
            Console.WriteLine(person.GetValue("Firstname").String & " " &
                              person.GetValue("Lastname").String)
        Next
    End Sub
End Module
