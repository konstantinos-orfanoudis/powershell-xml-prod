Option Strict On
' OIM520 violation: GetListFor called inside a loop — N+1 query pattern.
' Each iteration issues one or more additional database round-trips.

Imports VI.DB

Public Module OIM520_Violation
    Public Sub SyncGroupMembers(Session As ISession, groupIds As String())
        For Each groupUid As String In groupIds
            ' VIOLATION: GetListFor inside a loop — one SELECT per group.
            Dim members = Session.Source.GetListFor("ADSGroupMembership", "UID_ADSGroup",
                Session.Resolve(Of ISqlFormatter)().UidComparison("UID_ADSGroup", groupUid))
            Console.WriteLine(groupUid & " has " & members.Count.ToString() & " members")
        Next
    End Sub
End Module
