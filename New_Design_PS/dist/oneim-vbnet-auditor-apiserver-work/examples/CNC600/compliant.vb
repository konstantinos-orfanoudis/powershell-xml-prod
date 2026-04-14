Option Strict On
' CNC600 compliant: No NOLOCK hint; rely on READ_COMMITTED isolation (the default).

Imports VI.DB

Public Module CNC600_Compliant
    Public Sub LoadPendingAccounts(Session As ISession)
        ' Compliant: no NOLOCK; reads only committed data.
        Dim q As New Query("ADSAccount")
        q.WhereClause = "IsLocked = 0"
        q.Select("UID_ADSAccount")
        Dim collection = Session.Source.GetCollection(q)
    End Sub
End Module
