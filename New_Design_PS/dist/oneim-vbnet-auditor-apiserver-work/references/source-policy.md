# Approved Source Policy

Use this file when an audit needs authoritative backing for correctness, security, or performance findings.

## Default Version

- Active OneIM target version: `9.3.1`
- Official scripting guidance is currently anchored to the One Identity `9.3` Configuration Guide for several script topics.
- Treat those `9.3` pages as the nearest official version-matched scripting guidance for `9.3.1` unless One Identity later publishes more specific `9.3.1` pages for the same topics.

## Allowed Authorities

Only these approved authorities can contribute to findings:

1. Version-matched local One Identity API Server CHM pages indexed in `assets/apiserver-doc-index.json`
2. One Identity official docs on `support.oneidentity.com`
3. Microsoft Learn on `learn.microsoft.com`
4. OWASP on `cheatsheetseries.owasp.org` and `owasp.org`

## Evidence Priority

1. Local API Server CHM pages for version-matched API Server types, properties, and request-pipeline helpers
2. One Identity for broader OneIM behavior and version context
3. Microsoft Learn for VB.NET and .NET semantics, analyzers, reliability, and performance
4. OWASP for vulnerability-class guidance where vendor guidance is too generic or incomplete

## Blocked Sources

Never use these as authoritative support for a gating finding:

- blogs
- Stack Overflow
- forum posts
- GitHub issues
- AI summaries
- vendor marketing pages

## Approved Source Set

### Local OneIM API Server Docset

- Generated source index
  - `assets/apiserver-doc-index.json`
- Regeneration script
  - `scripts/generate_apiserver_doc_index.ps1`
- Notes
  - The generated index stores local `file:///` links to the extracted CHM HTML pages on the machine that generated it.
  - Regenerate the index after moving the skill to another machine or refreshing the installed One Identity documentation.

### OneIM And Version Context

- Product support anchor for `9.3.1`
  - https://support.oneidentity.com/identity-manager/9.3.1
- Testing scripts in the Script Editor
  - https://support.oneidentity.com/technical-documents/identity-manager/9.3/configuration-guide/scripts-in-one-identity-manager/testing-scripts-in-the-script-editor
- Creating and editing scripts in the Script Editor
  - https://support.oneidentity.com/technical-documents/identity-manager/9.3/configuration-guide/scripts-in-one-identity-manager/creating-and-editing-scripts-in-the-script-editor
- Overriding scripts
  - https://support.oneidentity.com/technical-documents/identity-manager/9.3/configuration-guide/scripts-in-one-identity-manager/overriding-scripts
- Using base objects and `Base.PutValue`
  - https://support.oneidentity.com/technical-documents/identity-manager/9.3/configuration-guide/scripts-in-one-identity-manager/using-base-objects
- System Debugger logging and performance context
  - https://support.oneidentity.com/technical-documents/identity-manager/9.3/configuration-guide/23

### VB.NET Correctness And Reliability

- `Option Strict`
  - https://learn.microsoft.com/en-us/dotnet/visual-basic/language-reference/statements/option-strict-statement
- `Option Explicit`
  - https://learn.microsoft.com/en-ca/dotnet/visual-basic/language-reference/statements/option-explicit-statement
- VB string and culture comparison guidance
  - https://learn.microsoft.com/en-us/dotnet/visual-basic/programming-guide/language-features/strings/how-culture-affects-strings
- Broad exception handling
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1031
- Disposable resource handling
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2000

### Security

- SQL injection and dynamic command text
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2100
  - https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html
- File path injection, path traversal, and file intake
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca3003
  - https://owasp.org/www-community/attacks/Path_Traversal
  - https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- Web requests, obsolete APIs, TLS, and certificate validation
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/syslib-diagnostics/syslib0014
  - https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca5359
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca5364
- Weak crypto and insecure parsing
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca5350
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca3075
  - https://cheatsheetseries.owasp.org/cheatsheets/XML_External_Entity_Prevention_Cheat_Sheet.html
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2300
  - https://learn.microsoft.com/lb-lu/dotnet/fundamentals/code-analysis/quality-rules/ca2310
- Process execution
  - https://cheatsheetseries.owasp.org/cheatsheets/OS_Command_Injection_Defense_Cheat_Sheet.html

### Performance

- `Count()` and `LongCount()` vs `Any()`
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1827
- Multiple enumeration of `IEnumerable`
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1851
- `StringBuilder` guidance
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/runtime-libraries/system-text-stringbuilder

## Rule Mapping

- SQL and DB access
  - Use `CA2100` plus OWASP SQL injection guidance for dynamic query construction, interpolated command text, string-built filters, and unsafe parameter handling.
- Web requests
  - Use `HttpClient` guidance and `SYSLIB0014` for API selection and lifecycle patterns.
  - Use `CA5359`, `CA5364`, and OWASP SSRF guidance for certificate validation, TLS posture, and user-controlled outbound requests.
- File reading and writing
  - Use `CA3003`, OWASP Path Traversal, and OWASP File Upload for user-controlled paths, upload flows, overwrite risk, and storage-location review.
- XML and deserialization
  - Use `CA3075`, OWASP XXE, `CA2300`, and `CA2310`.
- Process execution
  - Use OWASP OS Command Injection guidance for `Process.Start`, shell invocation, and argument passthrough.
- Reliability with security impact
  - Use `CA1031`, `CA2000`, `Option Strict`, `Option Explicit`, and VB string comparison guidance.
- Performance
  - Use `CA1827`, `CA1851`, `StringBuilder` guidance, and OneIM System Debugger query timing guidance to support expensive loop, enumeration, and DB access findings.

## Confidence Rules

- High confidence
  - direct code evidence
  - approved-source match
  - clear sink or failure mode
  - version-matched OneIM context when OneIM behavior matters
- Medium confidence
  - direct code evidence with approved generic .NET or OWASP guidance, but incomplete OneIM or runtime context
- Low confidence
  - heuristic smell without a clear sink
  - generalized OWASP-only pattern without strong local evidence
  - cross-version OneIM comparison

Never produce a gating finding from a blocked or unapproved source.

If an API family has no approved source yet, downgrade the result to `needs-manual-review`.
