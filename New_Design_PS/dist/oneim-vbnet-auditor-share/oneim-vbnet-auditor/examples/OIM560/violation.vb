Option Strict On
' OIM560 violation: TryGetSingleValue called multiple times on the same table
' with the same where clause — three separate SELECTs when one TryGet would suffice.

Imports VI.DB

Public Module OIM560_Violation
    Public Sub PrintPersonDetails(Session As ISession, personUid As String)
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        Dim where As String = f.UidComparison("UID_Person", personUid)

        ' VIOLATION: three SELECTs on "Person" using the same where clause.
        Dim firstName As Object = Session.Source.TryGetSingleValue("Person", "Firstname", where)
        Dim lastName As Object = Session.Source.TryGetSingleValue("Person", "Lastname", where)
        Dim email As Object = Session.Source.TryGetSingleValue("Person", "DefaultEmailAddress", where)

        If firstName IsNot Nothing Then
            Console.WriteLine(CStr(firstName) & " " & CStr(lastName) & " <" & CStr(email) & ">")
        End If
    End Sub
End Module
