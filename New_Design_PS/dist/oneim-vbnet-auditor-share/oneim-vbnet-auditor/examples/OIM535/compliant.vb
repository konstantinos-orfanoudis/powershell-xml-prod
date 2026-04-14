Option Strict On
' OIM535 compliant: String.IsNullOrEmpty for UID string check; .IsEmpty for FK objects.

Imports VI.DB

Public Module OIM535_Compliant
    Public Sub CheckHomeServer(person As IEntity, Session As ISession)
        ' Compliant: String.IsNullOrEmpty handles both Nothing and "" safely.
        If String.IsNullOrEmpty(person.GetValue("UID_HomeServer").String) Then
            Console.WriteLine("No home server assigned.")
        End If

        ' Compliant: for FK columns, .IsEmpty is even more semantically precise.
        If Not person.GetFk("UID_ADSContainer").IsEmpty Then
            Console.WriteLine("Container is set.")
        End If
    End Sub
End Module
