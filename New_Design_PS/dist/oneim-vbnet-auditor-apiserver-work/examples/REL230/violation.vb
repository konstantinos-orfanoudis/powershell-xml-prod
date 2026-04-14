Option Strict On
' REL230 violation: Empty Catch block silently swallows the exception.
' No log entry, no rethrow — provisioning silently produces wrong results.

Imports System

Public Module REL230_Violation
    Public Sub ProvisionAccount(accountId As String)
        Try
            DoWork(accountId)
        Catch ex As Exception
            ' VIOLATION: empty Catch — exception completely discarded.
        End Try

        Try
            DoMoreWork(accountId)
        Catch
            ' VIOLATION: even without a variable name — still empty.
        End Try
    End Sub

    Private Sub DoWork(id As String)
        Throw New InvalidOperationException("Work failed for " & id)
    End Sub

    Private Sub DoMoreWork(id As String)
        Throw New InvalidOperationException("More work failed for " & id)
    End Sub
End Module
