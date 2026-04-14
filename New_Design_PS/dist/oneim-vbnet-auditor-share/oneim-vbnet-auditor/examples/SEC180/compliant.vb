Option Strict On
' SEC180 compliant: Credentials loaded from the OneIM credential container at runtime.

Imports VI.DB
Imports VI.DB.ViClasses

Public Module SEC180_Compliant
    Public Sub ConnectToExternalService(Session As ISession)
        ' Compliant: retrieve secret from the OneIM credential container.
        Dim credContainer = Session.Source.GetSingle(Of IEntity)(
            "ExternalCredential",
            Session.Resolve(Of ISqlFormatter)().Comparison("Ident_Container", "REST-API-Key", ValType.String))

        If credContainer IsNot Nothing Then
            Dim apiKey As String = credContainer.GetValue("Password").String
            Console.WriteLine("Connecting with key from container.")
        End If
    End Sub
End Module
