Option Strict On
' SEC160 violation: BinaryFormatter used to deserialize data.
' BinaryFormatter is unsafe for untrusted data and disabled in .NET 5+ by default.

Imports System.IO
Imports System.Runtime.Serialization.Formatters.Binary

Public Module SEC160_Violation
    Public Function DeserializeObject(data As Byte()) As Object
        ' VIOLATION: BinaryFormatter allows arbitrary code execution via gadget chains.
        Dim formatter As New BinaryFormatter()
        Using ms As New MemoryStream(data)
            Return formatter.Deserialize(ms)
        End Using
    End Function
End Module
