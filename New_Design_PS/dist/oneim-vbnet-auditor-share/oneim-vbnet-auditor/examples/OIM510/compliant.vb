Option Strict On
' OIM510 compliant: VI-KEY CCC- prefix matches script name CCC_ prefix.

' VI-KEY <K>Custom</K><P>CCC-Person-DisplayName</P><N>CCC_GetPersonDisplayName</N>

Imports VI.DB

Public Module OIM510_Compliant
    Public Function CCC_GetPersonDisplayName(entity As IEntity) As String
        Return entity.GetValue("Firstname").String & " " & entity.GetValue("Lastname").String
    End Function
End Module
