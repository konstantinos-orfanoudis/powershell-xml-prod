Option Strict On
' OIM520 compliant: Load all memberships in one query; group in memory.

Imports System.Collections.Generic
Imports System.Linq
Imports VI.DB

Public Module OIM520_Compliant
    Public Sub SyncGroupMembers(Session As ISession, groupIds As String())
        ' Compliant: single bulk query for all groups; group in memory.
        Dim q As New Query("ADSGroupMembership")
        q.Select("UID_ADSGroup", "UID_ADSAccount")
        Dim allMembers = Session.Source.GetCollection(q)

        Dim grouped = allMembers.GroupBy(Function(e) e.GetValue("UID_ADSGroup").String).
            ToDictionary(Function(g) g.Key, Function(g) g.ToList())

        For Each groupUid As String In groupIds
            Dim memberList As List(Of IEntity) = Nothing
            Dim count As Integer = If(grouped.TryGetValue(groupUid, memberList), memberList.Count, 0)
            Console.WriteLine(groupUid & " has " & count.ToString() & " members")
        Next
    End Sub
End Module
