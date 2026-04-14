Option Strict On
' REL230 compliant: Catch block logs the exception and rethrows.

Imports System

Public Module REL230_Compliant
    Public Sub ProvisionAccount(accountId As String)
        Try
            DoWork(accountId)
        Catch ex As InvalidOperationException
            Console.Error.WriteLine("Provisioning failed for " & accountId & ": " & ex.Message)
            Throw
        End Try
    End Sub

    Private Sub DoWork(id As String)
        Throw New InvalidOperationException("Work failed for " & id)
    End Sub
End Module
