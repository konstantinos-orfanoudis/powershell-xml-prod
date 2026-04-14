Option Strict On
' OIM545 compliant: TryGetSingleValue() returns Nothing when no row exists — no exception.

Imports VI.DB

Public Module OIM545_Compliant
    Public Sub PrintHomeServerName(Session As ISession, personUid As String)
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        Dim where As String = f.UidComparison("UID_Person", personUid)

        ' Compliant: TryGetSingleValue returns Nothing instead of throwing.
        Dim result As Object = Session.Source.TryGetSingleValue("HomeServer", "ServerName", where)
        If result IsNot Nothing Then
            Console.WriteLine("Home server: " & CStr(result))
        Else
            Console.WriteLine("Home server: (not assigned)")
        End If
    End Sub
End Module
