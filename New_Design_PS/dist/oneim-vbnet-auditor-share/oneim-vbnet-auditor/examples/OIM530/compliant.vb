Option Strict On
' OIM530 compliant: f.UidComparison() for UID_ columns — handles empty-UID sentinel correctly.

Imports VI.DB

Public Module OIM530_Compliant
    Public Sub LoadByContainer(Session As ISession, uidContainer As String)
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()

        ' Compliant: UidComparison() is the correct method for UID_ columns.
        Dim where As String = f.UidComparison("UID_HomeServer", uidContainer)
        Dim q As New Query("ADSAccount")
        q.WhereClause = where
        Dim result = Session.Source.GetCollection(q)
    End Sub
End Module
