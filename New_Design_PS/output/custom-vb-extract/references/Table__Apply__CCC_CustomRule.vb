' Extracted from OneIM System Debugger export
' Source: Table\Table.vb:2-5
' custom_tokens: CCC_CustomRule
' kind: custom-reference-block
' symbol: Apply

    Public Sub Apply()
        Dim token = "CCC_CustomRule"
        Base.PutValue("Department", GetTriggerValue("Department").String)
    End Sub
