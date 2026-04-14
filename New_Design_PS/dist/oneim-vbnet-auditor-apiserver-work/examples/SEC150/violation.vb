Option Strict On
' SEC150 violation: XmlDocument loaded without disabling external DTD resolution.
' A crafted XML document can trigger XXE to read local files or SSRF.

Imports System.Xml

Public Module SEC150_Violation
    Public Function ParseXml(xmlContent As String) As XmlDocument
        ' VIOLATION: default XmlDocument allows external entity resolution.
        Dim doc As New XmlDocument()
        doc.LoadXml(xmlContent)
        Return doc
    End Function
End Module
