Option Strict On
' VB004 violation: = Nothing and <> Nothing used for reference-equality checks.
' In VB.NET, = Nothing uses value-equality which can behave unexpectedly for reference types.

Imports VI.DB

Public Module VB004_Violation
    Public Sub CheckEntity(entity As IEntity)
        ' VIOLATION: should use IsNot Nothing / Is Nothing for reference types.
        If entity <> Nothing Then
            Console.WriteLine("Entity exists: " & entity.GetValue("Firstname").String)
        End If

        If entity = Nothing Then
            Console.WriteLine("No entity provided.")
        End If
    End Sub
End Module
