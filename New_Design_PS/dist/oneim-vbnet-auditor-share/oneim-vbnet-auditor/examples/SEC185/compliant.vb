Option Strict On
' SEC185 compliant: Password loaded from OneIM credential container at runtime.

Imports System.Data.SqlClient
Imports VI.DB

Public Module SEC185_Compliant
    Public Function CreateConnection(Session As ISession) As SqlConnection
        ' Compliant: read the password from the OneIM credential container.
        Dim cred = Session.Source.GetSingle(Of IEntity)(
            "ExternalCredential",
            Session.Resolve(Of ISqlFormatter)().Comparison("Ident_Container", "ExtDB-Connection", ValType.String))

        Dim password As String = If(cred IsNot Nothing, cred.GetValue("Password").String, String.Empty)

        Dim builder As New SqlConnectionStringBuilder()
        builder.DataSource = "dbserver"
        builder.InitialCatalog = "OneIM"
        builder.UserID = "sa"
        builder.Password = password
        Return New SqlConnection(builder.ConnectionString)
    End Function
End Module
