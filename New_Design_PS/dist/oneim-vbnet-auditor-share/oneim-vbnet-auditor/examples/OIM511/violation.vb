Option Strict On
' OIM511 violation: VI-KEY with CCC- payload but Function name does not start with CCC_.

' VI-KEY <K>Custom</K><P>CCC-Person-Script</P>
' ^ VIOLATION: VI-KEY payload starts with CCC-, but the Function below is named
'   'GenerateUsername' — not CCC_GenerateUsername or CCC-GenerateUsername.

Imports VI.DB

Public Module OIM511_Violation
    Public Function GenerateUsername(entity As IEntity) As String
        Return (entity.GetValue("Firstname").String.Substring(0, 1) &
                entity.GetValue("Lastname").String).ToLower()
    End Function
End Module
