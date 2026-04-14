Option Strict On
' SEC160 compliant: Use System.Text.Json or DataContractJsonSerializer instead.

Imports System.Text.Json

Public Module SEC160_Compliant
    Public Function DeserializeObject(Of T)(json As String) As T
        ' Compliant: JSON deserialization with strict typing; no arbitrary code execution.
        Return JsonSerializer.Deserialize(Of T)(json)
    End Function
End Module
