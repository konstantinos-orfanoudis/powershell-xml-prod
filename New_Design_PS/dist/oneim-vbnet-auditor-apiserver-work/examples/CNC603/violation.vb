Option Strict On
' CNC603 violation: Thread.Sleep blocks the OneIM sync thread.
' This reduces throughput and can cause timeout cascades.

Imports System.Threading

Public Module CNC603_Violation
    Public Sub WaitForExternalSystem()
        ' VIOLATION: blocks the entire sync thread for 5 seconds.
        Thread.Sleep(5000)
        Console.WriteLine("Continuing after sleep...")
    End Sub
End Module
