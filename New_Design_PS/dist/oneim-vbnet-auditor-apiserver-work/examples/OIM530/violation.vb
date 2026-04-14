Option Strict On
' OIM530 violation: f.Comparison() used for a UID_ column instead of f.UidComparison().
' Generic string comparison misses OneIM's empty-UID sentinel and UID-specific SQL generation.

Imports VI.DB
Imports VI.DB.Compatibility

Public Module OIM530_Violation
    Public Sub LoadByContainer(Session As ISession, uidContainer As String)
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()

        ' VIOLATION: UID_ column compared as plain string — wrong method.
        Dim where As String = f.Comparison("UID_HomeServer", uidContainer, ValType.String)
        Dim q As New Query("ADSAccount")
        q.WhereClause = where
        Dim result = Session.Source.GetCollection(q)
    End Sub
End Module
