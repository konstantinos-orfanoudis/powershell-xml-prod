Option Strict On
' SEC100 compliant: Parameterised query via ISqlFormatter.
' No user input is concatenated into the SQL string.

Imports VI.DB
Imports VI.Base
Imports VI.DB.Compatibility

Public Module SEC100_Compliant
    Public Sub GetUser(Session As ISession, userName As String)
        ' Compliant: use the formatter to build a parameterised WHERE clause.
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        Dim where As String = f.Comparison("LastName", userName, ValType.String)
        Dim q As New Query("Person")
        q.WhereClause = where

        Dim collection = Session.Source.GetCollection(q)
    End Sub
End Module
