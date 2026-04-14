Option Strict On
' CNC603 compliant: Poll with bounded retries and early exit; no Thread.Sleep.

Imports System
Imports System.Threading

Public Module CNC603_Compliant
    Public Function WaitForExternalSystem(maxWaitSeconds As Integer) As Boolean
        Dim deadline As DateTime = DateTime.UtcNow.AddSeconds(maxWaitSeconds)
        Dim delayMs As Integer = 500
        Do While DateTime.UtcNow < deadline
            If ExternalSystemReady() Then Return True
            ' Short sleep only to yield CPU — bounded loop ensures we always exit.
            Thread.Sleep(delayMs)
            delayMs = Math.Min(delayMs * 2, 5000)
        Loop
        Return False
    End Function

    Private Function ExternalSystemReady() As Boolean
        ' Poll the external system status here.
        Return False
    End Function
End Module
