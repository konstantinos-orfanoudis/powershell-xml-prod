Option Strict On
' PER450 compliant: Connection pooling enabled (ADO.NET default; no Pooling=false).

Imports System.Data.SqlClient

Public Module PER450_Compliant
    Public Function GetConnection(password As String) As SqlConnection
        ' Compliant: pooling is on by default; connections are reused from the pool.
        Dim builder As New SqlConnectionStringBuilder()
        builder.DataSource = "db"
        builder.InitialCatalog = "OneIM"
        builder.UserID = "app"
        builder.Password = password
        ' No Pooling=false — default is pooling enabled.
        Return New SqlConnection(builder.ConnectionString)
    End Function
End Module
