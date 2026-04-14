Option Strict On
' OIM511 compliant: VI-KEY CCC- payload aligned with CCC_ Function name.

' VI-KEY <K>Custom</K><P>CCC-Person-Script</P>

Imports VI.DB

Public Module OIM511_Compliant
    Public Function CCC_GenerateUsername(entity As IEntity) As String
        Return (entity.GetValue("Firstname").String.Substring(0, 1) &
                entity.GetValue("Lastname").String).ToLower()
    End Function
End Module
