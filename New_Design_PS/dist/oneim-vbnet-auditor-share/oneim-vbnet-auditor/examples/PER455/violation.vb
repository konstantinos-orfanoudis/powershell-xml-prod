Option Strict On
' PER455 violation: BuildSessionFactory() called inside a helper method that runs per account.
' Rebuilding the factory for every provisioned record wastes significant time at scale.

Public Module PER455_Violation
    Public Sub ProvisionAccount(uid As String)
        ' VIOLATION: BuildSessionFactory() called on every invocation.
        Dim factory = BuildSessionFactory()
        Using session = factory.OpenSession()
            ' ... do work ...
        End Using
    End Sub

    Private Function BuildSessionFactory() As Object
        ' Simulates an expensive factory build.
        System.Threading.Thread.Sleep(200)
        Return New Object()
    End Function
End Module
