Option Strict On
' OIM535 violation: Direct = "" check on .GetValue("UID_...").String
' If GetValue returns Nothing instead of an empty string, the comparison silently evaluates to False.

Imports VI.DB

Public Module OIM535_Violation
    Public Sub CheckHomeServer(person As IEntity, Session As ISession)
        ' VIOLATION: = "" comparison on UID column — misses Nothing case.
        If person.GetValue("UID_HomeServer").String = "" Then
            Console.WriteLine("No home server assigned.")
        End If

        ' VIOLATION: <> "" on UID column.
        If person.GetValue("UID_ADSContainer").String <> "" Then
            Console.WriteLine("Container is set.")
        End If
    End Sub
End Module
