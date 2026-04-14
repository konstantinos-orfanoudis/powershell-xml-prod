Option Strict On
' CNC604 compliant: Loop with explicit iteration counter as secondary exit condition.

Imports System

Public Module CNC604_Compliant
    Public Sub ProcessQueue(queue As System.Collections.Queue)
        Dim maxIterations As Integer = 10000
        Dim iterations As Integer = 0
        Dim deadline As DateTime = DateTime.UtcNow.AddSeconds(30)

        Do While queue.Count > 0 AndAlso iterations < maxIterations AndAlso DateTime.UtcNow < deadline
            Dim item = queue.Dequeue()
            Console.WriteLine("Processed: " & CStr(item))
            iterations += 1
        Loop
    End Sub
End Module
