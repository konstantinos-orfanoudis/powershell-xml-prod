Option Strict On
' SEC190 violation: LDAP filter built by string concatenation — injection risk.
' A value containing special LDAP characters (e.g. *)(uid=*) can bypass the filter.

Imports System.DirectoryServices

Public Module SEC190_Violation
    Public Function FindUser(samAccountName As String) As DirectoryEntry
        ' VIOLATION: user input concatenated into LDAP filter string.
        Dim searcher As New DirectorySearcher()
        searcher.Filter = "(&(objectClass=user)(sAMAccountName=" & samAccountName & "))"
        Dim result = searcher.FindOne()
        Return If(result IsNot Nothing, result.GetDirectoryEntry(), Nothing)
    End Function
End Module
