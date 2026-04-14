Option Strict On
' PER430 compliant: Bulk load data before the loop; look up from an in-memory dictionary.

Imports System.Collections.Generic
Imports VI.DB

Public Module PER430_Compliant
    Public Sub ProcessAccounts(Session As ISession, accountIds As String())
        ' Compliant: load all needed data in one query before the loop.
        Dim f As ISqlFormatter = Session.Resolve(Of ISqlFormatter)()
        Dim q As New Query("Department")
        q.Select("UID_Person", "Name")
        Dim deptMap As New Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
        For Each row In Session.Source.GetCollection(q)
            deptMap(row.GetValue("UID_Person").String) = row.GetValue("Name").String
        Next

        For Each uid As String In accountIds
            Dim dept As String = String.Empty
            deptMap.TryGetValue(uid, dept)
            Console.WriteLine(uid & " -> " & dept)
        Next
    End Sub
End Module
