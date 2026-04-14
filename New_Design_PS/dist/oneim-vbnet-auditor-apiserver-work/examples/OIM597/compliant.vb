' OIM597 — COMPLIANT
' All department entities are loaded once with GetCollection before the loop.
' A dictionary keyed by UID_Department enables O(1) in-memory lookup per iteration.
' Total database round-trips: 2 (one for accounts, one for departments) regardless
' of how many accounts exist.

Public Sub SetDepartmentDisplay(Session As ISession)

    Dim accounts As IEntityCollection = Session.Source.GetCollection(Of IEntity)(
        "Person", "IsActive = 1")

    ' COMPLIANT: Load all departments in one query before the loop.
    Dim allDepts As IEntityCollection = Session.Source.GetCollection(Of IEntity)(
        "Department", "")

    ' Build an in-memory dictionary for O(1) lookup.
    Dim deptMap As New Dictionary(Of String, IEntity)
    For Each dept As IEntity In allDepts
        Dim uid As String = dept.GetValue("UID_Department").String
        If Not deptMap.ContainsKey(uid) Then
            deptMap(uid) = dept
        End If
    Next

    Using uow As IUnitOfWork = Session.StartUnitOfWork()
        For Each account As IEntity In accounts
            Dim deptUid As String = account.GetValue("UID_Department").String
            Dim matchedDept As IEntity = Nothing

            ' In-memory lookup — no SQL fired here.
            If deptMap.TryGetValue(deptUid, matchedDept) Then
                account.PutValue("CCC_DepartmentDisplay",
                    matchedDept.GetValue("Ident_Department").String)
                uow.Put(account)
            End If
        Next
        uow.Commit()
    End Using

End Sub
