Option Strict On
' OIM510 violation: VI-KEY comment uses CCC- prefix but script name does not.
' Custom scripts must be consistently named to distinguish them from OOTB logic.

' VI-KEY <K>Custom</K><P>CCC-Person-DisplayName</P><N>VI_GetPersonDisplayName</N>
' ^ VIOLATION: P starts with CCC- but the script name 'VI_GetPersonDisplayName'
'   does not start with CCC_ or CCC-.

Imports VI.DB

Public Module OIM510_Violation
    Public Function VI_GetPersonDisplayName(entity As IEntity) As String
        Return entity.GetValue("Firstname").String & " " & entity.GetValue("Lastname").String
    End Function
End Module
