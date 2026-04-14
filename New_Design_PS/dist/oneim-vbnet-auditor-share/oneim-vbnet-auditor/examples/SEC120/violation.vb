Option Strict On
' SEC120 violation: Broad Catch swallows all exceptions silently.
' Failures are hidden and the script continues in an undefined state.

Imports System

Public Module SEC120_Violation
    Public Sub ProcessAccount(accountId As String)
        Try
            DoProvisioningWork(accountId)
        Catch ex As Exception
            ' VIOLATION: exception swallowed — no rethrow, no logging.
        End Try
    End Sub

    Private Sub DoProvisioningWork(accountId As String)
        Throw New InvalidOperationException("Provisioning failed for " & accountId)
    End Sub
End Module
