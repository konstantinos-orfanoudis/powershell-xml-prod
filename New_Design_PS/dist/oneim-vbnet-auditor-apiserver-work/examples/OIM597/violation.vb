' OIM597 — VIOLATION
' TryGetSingleValue called inside a For Each loop.
' Each iteration issues a separate SELECT to load one department entity.
' With hundreds of accounts this produces hundreds of round-trips.

Public Sub SetDepartmentDisplay(Session As ISession)

    Dim accounts As IEntityCollection = Session.Source.GetCollection(Of IEntity)(
        "Person", "IsActive = 1")

    For Each account As IEntity In accounts
        Dim deptUid As String = account.GetValue("UID_Department").String

        ' VIOLATION: TryGetSingleValue fires one SELECT per loop iteration.
        Dim dept As IEntity = Nothing
        If Session.Source.TryGetSingleValue(Of IEntity)(
                "Department",
                "UID_Department = '" & deptUid & "'",
                dept) Then
            account.PutValue("CCC_DepartmentDisplay", dept.GetValue("Ident_Department").String)
            account.Save(Session)
        End If
    Next

End Sub
