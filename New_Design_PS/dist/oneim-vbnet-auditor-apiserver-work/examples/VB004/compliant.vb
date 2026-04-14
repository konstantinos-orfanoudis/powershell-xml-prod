Option Strict On
' VB004 compliant: Is Nothing / IsNot Nothing for reference-equality checks.

Imports VI.DB

Public Module VB004_Compliant
    Public Sub CheckEntity(entity As IEntity)
        If entity IsNot Nothing Then
            Console.WriteLine("Entity exists: " & entity.GetValue("Firstname").String)
        End If

        If entity Is Nothing Then
            Console.WriteLine("No entity provided.")
        End If
    End Sub
End Module
