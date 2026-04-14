Option Strict On
' CNC600 violation: WITH (NOLOCK) hint in SQL — reads uncommitted (dirty) data.

Imports VI.DB

Public Module CNC600_Violation
    Public Sub LoadPendingAccounts(Session As ISession)
        ' VIOLATION: NOLOCK can return rows that are still being written or rolled back.
        Dim sql As String = "SELECT UID_ADSAccount FROM ADSAccount WITH (NOLOCK) WHERE IsLocked = 0"
        Dim collection = Session.Source.GetCollectionFromSql(sql)
    End Sub
End Module
