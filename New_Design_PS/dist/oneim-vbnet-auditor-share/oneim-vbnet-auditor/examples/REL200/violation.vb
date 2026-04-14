Option Strict On
' REL200 violation: SqlCommand created without Using — resource leaked on exception.

Imports System.Data.SqlClient

Public Module REL200_Violation
    Public Function GetFirstName(connectionString As String, uid As String) As String
        Dim conn As New SqlConnection(connectionString)
        conn.Open()
        ' VIOLATION: SqlCommand not in a Using block; exception before .Close() leaks it.
        Dim cmd As New SqlCommand("SELECT Firstname FROM Person WHERE UID_Person = @uid", conn)
        cmd.Parameters.AddWithValue("@uid", uid)
        Dim result As Object = cmd.ExecuteScalar()
        conn.Close()
        Return If(result IsNot Nothing, CStr(result), String.Empty)
    End Function
End Module
