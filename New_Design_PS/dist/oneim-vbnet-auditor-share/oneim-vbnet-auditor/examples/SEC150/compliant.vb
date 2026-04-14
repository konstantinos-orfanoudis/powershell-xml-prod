Option Strict On
' SEC150 compliant: XmlReader with DTD processing prohibited.

Imports System.IO
Imports System.Xml

Public Module SEC150_Compliant
    Public Function ParseXml(xmlContent As String) As XmlDocument
        Dim settings As New XmlReaderSettings() With {
            .DtdProcessing = DtdProcessing.Prohibit,
            .XmlResolver = Nothing
        }
        Using reader As XmlReader = XmlReader.Create(New StringReader(xmlContent), settings)
            Dim doc As New XmlDocument() With {.XmlResolver = Nothing}
            doc.Load(reader)
            Return doc
        End Using
    End Function
End Module
