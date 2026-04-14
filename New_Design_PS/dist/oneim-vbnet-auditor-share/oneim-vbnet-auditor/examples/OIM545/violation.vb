Option Strict On
' OIM545 violation: Session.Source.GetSingleValue() throws when no row matches.
' If no record exists for the query, a ViException aborts the entire sync job.

Imports VI.DB

Public Module OIM545_Violation
    Public Sub PrintHomeServerName(Session As ISession, personUid As String)
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        Dim where As String = f.UidComparison("UID_Person", personUid)

        ' VIOLATION: GetSingleValue throws ViException when no row matches.
        Dim serverName As String = CStr(Session.Source.GetSingleValue("HomeServer", "ServerName", where))
        Console.WriteLine("Home server: " & serverName)
    End Sub
End Module
