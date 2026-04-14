Option Strict On
' SEC180 violation: Hardcoded credential literals embedded in script code.
' Anyone with access to the script or its export can read the credentials.

Public Module SEC180_Violation
    Public Sub ConnectToExternalService()
        ' VIOLATION: credentials hardcoded as literals — leaked in every export.
        Dim password As String = "P@ssw0rd123"
        Dim apiKey As String = "sk-live-abc1234567890"
        Dim clientSecret As String = "MyS3cretV@lue"

        Console.WriteLine("Connecting with key: " & apiKey)
    End Sub
End Module
