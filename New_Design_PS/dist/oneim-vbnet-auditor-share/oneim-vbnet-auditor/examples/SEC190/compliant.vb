Option Strict On
' SEC190 compliant: LDAP special characters escaped before embedding in filter.

Imports System
Imports System.DirectoryServices
Imports System.Text.RegularExpressions

Public Module SEC190_Compliant
    ''' <summary>Escapes special LDAP filter characters per RFC 4515.</summary>
    Private Function EscapeLdapFilter(value As String) As String
        Return value.Replace("\", "\5c").Replace("*", "\2a").Replace("(", "\28").
                     Replace(")", "\29").Replace(Chr(0), "\00")
    End Function

    Public Function FindUser(samAccountName As String) As DirectoryEntry
        Dim safeName As String = EscapeLdapFilter(samAccountName)
        Dim searcher As New DirectorySearcher()
        searcher.Filter = "(&(objectClass=user)(sAMAccountName=" & safeName & "))"
        Dim result = searcher.FindOne()
        Return If(result IsNot Nothing, result.GetDirectoryEntry(), Nothing)
    End Function
End Module
