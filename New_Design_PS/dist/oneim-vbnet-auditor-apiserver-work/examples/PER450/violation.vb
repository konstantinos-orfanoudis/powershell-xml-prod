Option Strict On
' PER450 violation: ADO.NET connection pooling disabled with Pooling=false.
' Every operation forces a full TCP handshake and authentication round-trip.

Imports System.Data.SqlClient

Public Module PER450_Violation
    Public Function GetConnection() As SqlConnection
        ' VIOLATION: Pooling=false — new connection opened every time, very slow at scale.
        Dim connStr As String = "User ID=app;Password=pwd;Data Source=db;Pooling=false;Initial Catalog=OneIM"
        Return New SqlConnection(connStr)
    End Function
End Module
