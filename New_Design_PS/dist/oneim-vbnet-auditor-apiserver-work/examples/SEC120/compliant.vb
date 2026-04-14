Option Strict On
' SEC120 compliant: Catch specific exception types and log or rethrow.

Imports System
Imports VI.Base

Public Module SEC120_Compliant
    Public Sub ProcessAccount(accountId As String)
        Try
            DoProvisioningWork(accountId)
        Catch ex As InvalidOperationException
            ' Compliant: log the failure and rethrow so the sync engine records it.
            VILog.Error("ProcessAccount failed for " & accountId & ": " & ex.Message)
            Throw
        End Try
    End Sub

    Private Sub DoProvisioningWork(accountId As String)
        Throw New InvalidOperationException("Provisioning failed for " & accountId)
    End Sub
End Module
