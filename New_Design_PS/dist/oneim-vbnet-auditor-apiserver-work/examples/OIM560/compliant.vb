Option Strict On
' OIM560 compliant: TryGet loads the entity once — same safe-return behaviour as
' TryGetSingleValue (returns Nothing when no row matches) but only one SELECT.

Imports VI.DB

Public Module OIM560_Compliant
    Public Sub PrintPersonDetails(Session As ISession, personUid As String)
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        Dim where As String = f.UidComparison("UID_Person", personUid)

        ' Compliant: TryGet returns Nothing when no row matches — one SELECT, all columns in memory.
        Dim person As IEntity = Session.Source.TryGet(Of IEntity)("Person", where)
        If person Is Nothing Then
            Console.WriteLine("Person not found.")
            Return
        End If

        Dim firstName As String = person.GetValue("Firstname").String
        Dim lastName As String = person.GetValue("Lastname").String
        Dim email As String = person.GetValue("DefaultEmailAddress").String

        Console.WriteLine(firstName & " " & lastName & " <" & email & ">")
    End Sub
End Module
