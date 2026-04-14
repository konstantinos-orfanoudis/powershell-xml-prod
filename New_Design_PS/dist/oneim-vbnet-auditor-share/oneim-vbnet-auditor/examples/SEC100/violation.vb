Option Strict On
' SEC100 violation: SQL query built by string concatenation.
' User-controlled input can inject arbitrary SQL.

Imports VI.DB
Imports VI.Base

Public Module SEC100_Violation
    Public Sub GetUser(Session As ISession, userName As String)
        ' VIOLATION: user input appended directly into SQL string.
        Dim sql As String = "SELECT * FROM Person WHERE LastName = '" & userName & "'"
        Dim collection = Session.Source.GetCollectionFromSql(sql)
    End Sub
End Module
