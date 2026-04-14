Option Strict On
' REL200 compliant: All disposable objects wrapped in Using blocks.

Imports System.Data.SqlClient

Public Module REL200_Compliant
    Public Function GetFirstName(connectionString As String, uid As String) As String
        Using conn As New SqlConnection(connectionString)
            conn.Open()
            Using cmd As New SqlCommand("SELECT Firstname FROM Person WHERE UID_Person = @uid", conn)
                cmd.Parameters.AddWithValue("@uid", uid)
                Dim result As Object = cmd.ExecuteScalar()
                Return If(result IsNot Nothing, CStr(result), String.Empty)
            End Using
        End Using
    End Function
End Module
