Option Strict On
' PER455 compliant: Session factory built once at module initialisation and reused.

Public Module PER455_Compliant
    ' Compliant: factory built once, lazily, and reused for all subsequent calls.
    Private ReadOnly _factory As New Lazy(Of Object)(Function() CreateFactory())

    Public Sub ProvisionAccount(uid As String)
        Using session = _factory.Value
            ' ... do work — factory is not rebuilt here ...
        End Using
    End Sub

    Private Function CreateFactory() As Object
        ' Expensive factory initialisation happens only once.
        System.Threading.Thread.Sleep(200)
        Return New Object()
    End Function
End Module
