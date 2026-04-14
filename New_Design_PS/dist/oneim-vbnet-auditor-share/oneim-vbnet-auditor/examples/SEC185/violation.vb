Option Strict On
' SEC185 violation: Database password embedded inside a connection string literal.
' The credential is visible in version control and every OneIM export package.

Imports System.Data.SqlClient

Public Module SEC185_Violation
    Public Function CreateConnection() As SqlConnection
        ' VIOLATION: password in connection string literal — leaked in exports.
        Dim connStr As String = "User ID=sa;Password=Secret123;Data Source=dbserver;Initial Catalog=OneIM"
        Return New SqlConnection(connStr)
    End Function
End Module
