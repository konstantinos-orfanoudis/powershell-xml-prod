# XML-Validator Rule Summary

This file documents the validation policy behind the `/XML-Validator` page.

It is meant as a maintenance note for improving, relaxing, or replacing the current validator behavior.

## Current Validation Mode

The active `/XML-Validator` page now uses AI-first validation.

- The rules in this document are passed to the AI route as the validation prompt.
- The AI route also adds an internal SSCP tutor policy layer to sharpen PowerShell security, resilience, and maintainability review.
- The AI route also adds an auditor-approved reference layer so PowerShell findings can include Microsoft Learn, OWASP, NVD, CISA, and relevant vendor advisory links when they fit the finding.
- The AI route is responsible for producing the structured validation findings shown in the UI.
- The older deterministic validators are still in the repo as reference logic, but they are no longer the active engine used by `/XML-Validator`.

## Main Rule Files

The repo still contains three relevant validator-related files:

1. `app/utils/validation.ts`
   Base XML, schema, and binding checks. This is now legacy reference logic.
2. `app/XML-Validator/validation.ts`
   XML-Validator-specific deterministic logic. This is now legacy reference logic.
3. `app/api/ai/xml-validator/route.ts`
   The active AI validator route. It uses this rules document as a prompt and returns the structured findings used by the UI.

## Execution Flow

The active execution flow is AI-only:

1. The page uploads the connector XML and PowerShell script to `app/api/ai/xml-validator/route.ts`.
2. The route reads this markdown file and includes it in the prompt sent to the model.
3. The route enriches the prompt with the internal SSCP tutor material most relevant to connector security and PowerShell quality.
4. The route enriches the prompt with the auditor-approved source model and inferred product/vendor context for advisory or CVE-style follow-up links.
5. The model performs the validation directly, using these rules as policy guidance.
6. The route normalizes the output and can attach approved policy or advisory references to PowerShell findings before returning the final report to the UI.

Legacy deterministic files remain in the repo as reference material for future maintenance, but they are not executed by the active `/XML-Validator` page.

## Important Assumptions

These assumptions matter if you want to change validator behavior:

- Global PowerShell functions must be declared as `function global:Name`.
- Entity expectations come from PowerShell function names via `parseFnName()`.
- Verb mapping is:
  `Get -> List`
  `Create -> Insert`
  `Update -> Update`
  `Delete -> Delete`
- The validator expects the XML root to be `<PowershellConnectorDefinition>`.
- Connection parameters are inferred from global function parameters, excluding names that already look like entity property names.
- `PathToPSModule` is no longer force-added by the XML-Validator.
- Module-path support is only inferred when the uploaded XML or PowerShell explicitly uses a module-path-style parameter name such as `PathToPSModule`, `_PathToPSModule`, `ModulePath`, or similar.
- Custom commands are parsed from XML only when they follow the `<CustomCommand Name="..."><![CDATA[...]]></CustomCommand>` pattern.
- Return-bind validation only understands return shapes it can infer from `[pscustomobject] @{ ... }` blocks in PowerShell.

## Base Rule Catalog

These rule codes and meanings are still useful as validation guidance for the AI route.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `xml.declaration.normalized` | warning | The XML declaration was normalized for validation because it used a non-standard declaration pattern such as `utf-8 with BOM`. |
| `xml.parse` | error | XML must be well-formed. If parsing fails, validation stops early. |
| `xml.ok` | info | XML parsed successfully. |
| `ps.none` | warning | No global PowerShell functions were found by the generic parser. |
| `ps.count` | info | Number of detected global PowerShell functions. |
| `schema.entities` | info | Number of schema entities loaded. |
| `xml.attr.whitespace` | warning | XML attribute contains only whitespace. |
| `xml.attr.newline` | warning | XML attribute contains a newline. |
| `bind.missing.command` | error | `<ReturnBind>` or `<ReturnBinding>` is missing `commandResultOf`. |
| `bind.fn.unknown` | error | ReturnBind points to a PowerShell function that does not exist. |
| `bind.path.empty` | warning | ReturnBind path is empty. |
| `bind.missing.fromto` | error | `<Bind>` is missing `from` and/or `to`. |
| `schema.property.missing` | error | A ReturnBind path points to a property not found in the inferred entity schema. |
| `schema.entity.unknown` | info | Entity context could not be inferred for a ReturnBind path check. |
| `xml.root.missing` | error | XML has no root element. |
| `xml.root.noname` | warning | Root element exists but has no `name` attribute. |
| `xml.name.duplicate` | warning | Duplicate `name` attribute values were found in the XML. |
| `xml.text.ws` | info | Whitespace-only text node detected. Mostly informational. |

## XML-Validator Rule Catalog

These rules are also available to the AI route as policy guidance.

### Input and Parsing Rules

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `validator.xml.empty` | warning | No XML was provided. |
| `validator.ps.empty` | warning | No PowerShell file was provided. |
| `xml.root.connector` | warning | Root element is not `<PowershellConnectorDefinition>`. |
| `ps.global.none` | warning | PowerShell text exists, but no `function global:...` signatures were found for XML-builder-style validation. |

### Predefined Command Coverage

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `xml.predefined.missing-global` | error | A predefined XML command does not match a PowerShell function contained in the uploaded script. |

Notes:

- `<PredefinedCommands>` should declare commands that are actually implemented as PowerShell functions in the uploaded script.
- If XML relies on a predefined command name that is not backed by a PowerShell function in the uploaded script, that is an error.

### Entity and CRUD Coverage Rules

These rules cover both XML class structure requirements and PowerShell-driven class coverage.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `xml.class.read-config.missing` | error | Every `<Class>` must contain a `<ReadConfiguration>` section. |
| `xml.class.listing-command.missing` | error | Every class `<ReadConfiguration>` must contain a `<ListingCommand Command="...">`. |
| `xml.class.item-command.missing` | error | Every class `<ReadConfiguration>` must contain an item-read command, either as `<Item Command="...">` directly or as `<CommandSequence><Item Command="...">...</Item></CommandSequence>`. |
| `xml.class.listing-command.not-list` | error | The class `ListingCommand` does not appear to return a list of objects, directly or indirectly, when the PowerShell is analyzed with AI. |
| `xml.class.item-command.not-single` | error | The class `Item` command does not appear to return a single object, directly or indirectly, when the PowerShell is analyzed with AI. |
| `xml.class.item-command.same-as-listing.unsupported` | error | `Item` uses the same command as `ListingCommand`, but the PowerShell does not show a credible branch or mode that returns a single object. |
| `signature.class.missing` | warning | PowerShell implies an entity, but the XML has no `<Class Name="...">`. |
| `signature.read-config.missing` | error | PowerShell implies list/read behavior, but the class has no `<ReadConfiguration>`. |
| `signature.method.insert.missing` | warning | PowerShell implies create behavior, but the class has no `<Method Name="Insert">`. |
| `signature.method.update.missing` | warning | PowerShell implies update behavior, but the class has no `<Method Name="Update">`. |
| `signature.method.delete.missing` | warning | PowerShell implies delete behavior, but the class has no `<Method Name="Delete">`. |
| `signature.class.unmatched` | info | The XML class exists, but no matching CRUD/list PowerShell signature was inferred for it. |

Notes:

- The structural requirement is unconditional: every XML class is expected to expose `<ReadConfiguration>`, `<ListingCommand>`, and an item-read `<Item>` command, even if PowerShell signature inference is incomplete.
- For this rule, `<Item>` is valid either directly under `<ReadConfiguration>` or nested inside `<ReadConfiguration><CommandSequence>...</CommandSequence>`.
- `ListingCommand` must look list-returning from the PowerShell behavior, not just from its name.
- `Item` must look single-object-returning from the PowerShell behavior, not just from its name.
- If `Item` and `ListingCommand` use the same PowerShell function, that is valid only when the AI can see a believable branch, filter, or parameter-driven path that returns a single object for item reads.
- For item reads, "single-object-returning" also includes the common connector pattern where the PowerShell filters by a unique key or equivalent identifier and returns a collection that effectively contains zero or one object.
- Do not raise `xml.class.item-command.not-single` or `xml.class.item-command.same-as-listing.unsupported` when the shared read command credibly narrows by the item's unique key and would normally yield at most one matching object, even if the final PowerShell return value is still an array/list wrapper.

### Property Rules

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `property.data-type.invalid` | error | A `<Property>` uses a `DataType` value other than `String`, `Int`, `Bool`, or `DateTime`. |

Notes:

- The only valid XML property `DataType` values are `String`, `Int`, `Bool`, and `DateTime`.

### Connection Parameter Rules

These compare XML connection parameters with parameters inferred from global PowerShell function signatures.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `signature.connection-parameter.missing` | warning | A connection parameter is implied by global PowerShell signatures but missing in XML. |
| `signature.connection-parameter.extra` | info | XML contains a connection parameter not inferred from global PowerShell signatures. |
| `connection-parameter.sensible-data.missing` | warning | A `<ConnectionParameter>` looks like it carries a password, token, key, secret, or similar sensitive value, but it does not use `IsSensibleData="true"`. |

Notes:

- A module-path connection parameter such as `PathToPSModule` should only be expected when that pattern is explicitly present in the uploaded XML or PowerShell input.
- `Get-Authorization` is treated as a builder convention, not as a required XML-validator rule.
- Infer sensitive connection parameters from both `Name` and `Description`, using cues such as `password`, `secret`, `token`, `api key`, `client secret`, `private key`, `access key`, `refresh token`, or similar wording.
- Do not require `IsSensibleData="true"` for clearly non-sensitive values such as URLs, tenant names, site names, or usernames unless the surrounding context strongly suggests a secret.

### Command Declaration and Command Reference Rules

These check whether the commands used in XML are both declared and implemented.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `xml.custom-command.cdata.missing` | error | A `<CustomCommand>` does not wrap its PowerShell body in `<![CDATA[ ... ]]>`. |
| `xml.command.undeclared` | error | A command is used in XML but not declared in `<PredefinedCommands>` or `<CustomCommands>`. |
| `xml.command.missing` | error | A command is referenced in XML but does not exist in the PowerShell file or XML custom commands. |
| `xml.class.returnbind.listing-command.missing` | error | The same class does not expose a return-binding path that uses its `ListingCommand`. |
| `xml.class.returnbind.item-command.missing` | error | The same class does not expose a return-binding path that uses its `Item` command. |
| `xml.class.returnbind.command.invalid` | error | A class `ReturnBinding` uses a command other than the class `ListingCommand` or `Item` command defined in the same `ReadConfiguration`. |
| `map.parameter.missing` | error | In `<CommandMappings>`, a `<Map Parameter="...">` must match an existing parameter of the referenced PowerShell function, but the named parameter does not exist on that function. |
| `map.type.mismatch` | error | A mapped XML property type does not match the target PowerShell parameter type. |
| `map.parameter.name-mismatch` | warning | `<Map Parameter="...">` does not match the XML property name, which differs from the builder convention. |
| `modby.method.command.missing` | warning | A command used in a class `<ModifiedBy>` section is not also used in the `<MethodConfiguration>` of the same class, typically under `Insert` or `Update`. |
| `bind.path.not-returned` | error | A `<Bind>` path does not exist in the inferred PSCustomObject returned by the command. |
| `bind.type.mismatch` | error | XML property type does not match the inferred PSCustomObject return property type. |

Notes:

- The dynamic rule templates `${ref.tag.toLowerCase()}.parameter.missing` and `${ref.tag.toLowerCase()}.type.mismatch` currently matter mainly for `<Map>` because it is the command reference that carries a `Parameter="..."` attribute into the comparison logic.
- In `<CommandMappings>`, the `Parameter` field should name a real parameter on the corresponding PowerShell function referenced by that mapping.
- `<CustomCommand Name="...">` should contain its PowerShell body inside a CDATA section, for example `<![CDATA[ Import-Module MyModule -Force ]]>`.
- `<ListingCommand>` and the effective item-read command are structurally required for every class `ReadConfiguration`, and their referenced commands should also be checked for declaration and existence.
- Treat `<ReadConfiguration><CommandSequence><Item Command="...">...</Item></CommandSequence></ReadConfiguration>` as a valid item-read structure.
- The AI should reason about whether `ListingCommand` looks list-returning and whether `Item` looks single-object-returning, even when the script achieves that indirectly through helper functions, branching, pipelines, loops, or `Select-Object`.
- Return bindings should be checked in the context of the same class: the class should expose bindings for its read commands rather than relying on unrelated command bindings elsewhere in the XML.
- In the same class, `ReturnBinding` should only use commands that come from that class `ReadConfiguration`, specifically the `ListingCommand` or `Item` command.
- If the same command is used for both `ListingCommand` and `Item`, one shared set of class-level `ReturnBindings` referencing that command is enough to satisfy both read modes. Do not require duplicate bindings just because the command appears in both places.
- `ModifiedBy` is checked both for command existence and for whether that same command is also used in the `<MethodConfiguration>` of the same class, typically under `Insert` or `Update`.

### Environment Initialization Rules

These rules are heuristic and AI-driven. They are meant to help identify the expected initialization flow rather than enforce a rigid template.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `environment-init.import-first.missing` | warning | The first command in `<EnvironmentInitialization>` does not appear to import the PowerShell module by path or hardcoded module name. |
| `environment-init.import-order.invalid` | warning | The first initialization command should use `Order="1"`, but the XML does not reflect that expected order. |
| `environment-init.connect-command.missing` | warning | The initialization sequence does not clearly include a connect/authentication command after the module import step. |
| `environment-init.connect-command.unknown` | warning | A likely connect/authentication command is referenced in initialization, but it cannot be matched confidently to a custom command or PowerShell function in the uploaded inputs. |
| `environment-init.connect-order.invalid` | warning | The connect/authentication step should usually be the second initialization command with `Order="2"`, but the XML does not reflect that expected order. |

Notes:

- The first initialization step should usually be a module import command, either via `Import-Module <ModuleName>` or via a path-based import pattern.
- The next step should usually be a connect/authentication command that prepares access to the target system, often by setting global variables, tokens, sessions, headers, or similar shared state.
- When the initialization sequence is explicit, the first command should usually have `Order="1"` and the next connect/authentication step should usually have `Order="2"`.
- The connect/authentication step may be implemented as either a predefined command or a custom command.
- To identify the connect/authentication step, inspect the XML `<EnvironmentInitialization>` section together with the `<CustomCommands>` section and the uploaded PowerShell script.
- Treat this as a heuristic rule: when the evidence is ambiguous, prefer a warning and explain the uncertainty rather than emitting a hard error.

### `<SetParameter>` Rules

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `set-parameter.param.missing` | error | `<SetParameter>` is missing `Param="..."`. |
| `set-parameter.command.missing` | error | `<SetParameter>` is not nested under an XML command element that exposes `Command="..."`. |
| `set-parameter.source.invalid` | error | `<SetParameter>` uses a `Source` value other than `FixedValue`, `ConnectionParameter`, `GlobalVariable`, `SwitchParameter`, or `FixedArray`. |
| `set-parameter.connection.value.missing` | error | `Source="ConnectionParameter"` is used, but `<SetParameter>` does not provide a `Value="..."` attribute naming the XML connection parameter to use. |
| `set-parameter.connection.missing` | error | `Source="ConnectionParameter"` is used, but the `Value` does not match any existing `<ConnectionParameter Name="...">` in the XML. |
| `set-parameter.signature.missing` | error | The target command does not expose the requested parameter. |
| `set-parameter.signature.type` | warning | A connection parameter is flowing into a non-string PowerShell parameter. |

Notes:

- The only valid `Source` values for `<SetParameter>` are `FixedValue`, `ConnectionParameter`, `GlobalVariable`, `SwitchParameter`, and `FixedArray`.
- When `Source="ConnectionParameter"`, the `Value` attribute should exactly match the `Name` of an existing XML `<ConnectionParameter>`.

### PowerShell Script Security And Performance Audit

These checks are AI-driven and focus on the uploaded PowerShell script itself. They should produce a rule-by-rule report with evidence, severity, and a concrete fix suggestion.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `ps.security.hardcoded.secret` | error | The PowerShell script contains hardcoded credentials, tokens, keys, connection strings, or other embedded secrets. |
| `ps.security.secret.comment` | error | PowerShell comments or disabled code appear to expose sensitive values or operational secrets. |
| `ps.security.insecure-remote-call` | warning | Remote calls appear to weaken TLS or certificate validation, trust all certificates, or build insecure authentication flows. |
| `ps.security.excessive-global-state` | warning | The script stores sensitive or connection-critical state in globals more broadly than necessary. |
| `ps.security.sql-injection` | error | SQL queries, commands, or filters appear to be built by concatenating or interpolating untrusted input instead of using safer parameterization patterns. |
| `ps.security.ldap-injection` | error | LDAP filters, search bases, or directory queries appear to inject untrusted input directly without safe escaping or validation. |
| `ps.security.remote-filter-injection` | warning | REST, cloud, or other remote-system filters, paths, headers, or request bodies appear to insert untrusted input directly in a way that could alter query meaning or scope. |
| `ps.security.tls-weakened` | error | The script appears to weaken transport security, such as disabling certificate checks, forcing insecure protocols, or using plain HTTP for sensitive traffic. |
| `ps.security.http-request.insecure` | warning | HTTP or cloud requests appear to omit important security precautions such as safe authentication handling, explicit HTTPS usage, request validation, or controlled redirect behavior. |
| `ps.quality.encoding.missing` | warning | Web requests (Invoke-WebRequest / Invoke-RestMethod / HttpClient) do not specify UTF-8 encoding explicitly in the Content-Type header or body serialization, and the context does not require a different charset. Expect `charset=utf-8` in the Content-Type header and UTF-8-aware body serialization unless the API documentation explicitly requires otherwise. |
| `ps.performance.repeated-import` | warning | The script appears to repeat module imports, expensive initialization, or setup logic unnecessarily. |
| `ps.performance.loop-remote-call` | warning | The script appears to perform repeated remote/API calls inside loops without batching, caching, or early filtering. |
| `ps.performance.unbounded-processing` | warning | The script appears to process large result sets without paging, filtering, or early exit where that would be expected. |
| `ps.performance.redundant-transformation` | warning | The script appears to do avoidable repeated conversions, object rebuilding, or data reshaping that could be simplified. |
| `ps.quality.logging.missing` | warning | The script lacks clear operational logging around important steps, failures, or external-system calls. |
| `ps.logging.timestamp.missing` | warning | Log entries do not include timestamps or use local time without UTC normalization. Every log record should include a UTC timestamp in ISO 8601 format (`[datetime]::UtcNow.ToString('o')`). NIST SP 800-92 §2.1.1; NIST SP 800-53 AU-8. |
| `ps.logging.actor.missing` | warning | Log entries do not record the actor or identity (service account, user) performing the operation. NIST SP 800-92 §2.1.4; NIST SP 800-53 AU-3. |
| `ps.logging.event-type.missing` | warning | Log entries do not include a consistent event-type label (e.g. `FunctionStart`, `ApiCall`, `EntityCreate`, `Error`). Without a type label, logs cannot be reliably filtered or correlated. NIST SP 800-92 §2.1.2; NIST SP 800-53 AU-3. |
| `ps.logging.outcome.missing` | warning | Log entries do not record the outcome (Success/Failure) of significant operations. Every data operation and external call should conclude with an explicit outcome log. NIST SP 800-92 §2.1.5; NIST SP 800-53 AU-3. |
| `ps.logging.secret.exposure` | error | Log entries appear to include plaintext passwords, tokens, API keys, or other secrets. All sensitive values must be replaced with `[REDACTED]` before writing to any log sink. NIST SP 800-92 §2.2; NIST SP 800-53 AU-9. |
| `ps.logging.auth-events.missing` | warning | Authentication or connection-establishment events are not logged. The connect step (and its outcome) must be recorded without exposing credentials. NIST SP 800-92 §3.2; NIST SP 800-53 AU-2. |
| `ps.logging.crud-operations.missing` | warning | Create, Update, or Delete operations on data entities are not logged with entity type, identifier, and outcome. Read operations that access sensitive or large data sets should also be logged. NIST SP 800-92 §3.2; NIST SP 800-53 AU-2. |
| `ps.logging.external-calls.missing` | warning | External API or service calls (REST, SOAP, SCIM, SQL) are not logged with HTTP method, sanitized URL, and response status code or error type. NIST SP 800-92 §3.2; NIST SP 800-53 AU-12. |
| `ps.logging.error-context.insufficient` | warning | Exception or error handling does not log enough context for investigation: at minimum log exception type, message, entity or resource being acted on, and the operation that failed. NIST SP 800-92 §3.2; NIST SP 800-53 AU-3. |
| `ps.logging.structured.missing` | warning | Script uses `Write-Host` or `Write-Output` for operational logging instead of a structured, centralized logger (NLog / `Get-Logger`). Unstructured console output cannot be captured, indexed, or protected by log management infrastructure. NIST SP 800-92 §4; NIST SP 800-53 AU-9. |
| `ps.logging.function-boundary.missing` | warning | Functions do not log entry and exit (including outcome and duration). Without boundary markers it is impossible to trace the flow of a connector operation end-to-end. NIST SP 800-92 §3.2; NIST SP 800-53 AU-12. |
| `ps.quality.trycatch.missing` | warning | The script performs important operations without meaningful `try/catch` protection where failures should be handled or surfaced. |
| `ps.quality.throw.missing` | warning | The script appears to catch or detect failures without escalating them properly with `throw` or an equivalent terminating error. |
| `ps.quality.comments.insufficient` | warning | The script or module lacks enough helpful comments around non-obvious logic, connector-specific decisions, or integration behavior to be easy to understand and extend. |
| `ps.quality.function-complexity.high` | warning | Functions appear too long, too dense, or responsible for too many concerns, making the script harder to change safely. |
| `ps.quality.naming.unclear` | warning | Function, variable, or helper names appear vague or inconsistent, making connector behavior harder to understand quickly. |
| `ps.quality.structure.maintainability.low` | warning | The script structure makes the connector harder to extend, test, or modify, for example through duplicated logic, mixed responsibilities, or weak separation of concerns. |
| `ps.security.least-privilege.missing` | warning | The script requests, stores, or forwards broader permissions or credentials than the operation requires. Credentials should be scoped to the minimum required for each function. NIST SP 800-53 AC-6; NIST SP 800-218 PW.5. |
| `ps.security.input-validation.missing` | warning | Parameters or data flowing in from external systems are used in queries, API calls, or commands without visible validation, sanitization, or type checking at the boundary. NIST SP 800-218 PW.5; NIST SP 800-53 SI-10. |
| `ps.security.credential-rotation.missing` | warning | The script uses long-lived tokens, bearer tokens, or session credentials with no visible expiry check, refresh logic, or error handling for expired-credential responses (HTTP 401/403). NIST SP 800-53 IA-5; NIST SP 800-63B §5.2.3. |
| `ps.security.timeout.missing` | warning | Web requests or external calls (Invoke-WebRequest, Invoke-RestMethod, HttpClient, SqlCommand) do not set an explicit timeout. Unbounded waits allow slow or unresponsive services to stall the connector indefinitely and can be exploited for resource exhaustion. NIST SP 800-53 SC-5; NIST SP 800-204 §3.3. |
| `ps.security.error-disclosure.risk` | warning | Exception messages, error details, or stack traces may be forwarded to callers or external systems without scrubbing, potentially exposing internal paths, schema details, or system configuration. NIST SP 800-53 SI-11; NIST SP 800-218 RV.1. |
| `ps.security.insecure-deserialization` | error | The script deserializes JSON, XML, or other formats from an external or untrusted source (ConvertFrom-Json, [xml], XmlDocument) without validating structure, type, or size before use. Malformed or oversized payloads can cause unexpected behavior or resource exhaustion. NIST SP 800-218 PW.6; NIST SP 800-53 SI-10. |
| `ps.security.open-redirect.risk` | warning | A URL or redirect target is constructed from untrusted external input without validation, which could be manipulated to redirect traffic to an attacker-controlled endpoint. NIST SP 800-204 §3.2; OWASP A10. |
| `ps.security.header-injection.risk` | warning | HTTP headers are assembled by concatenating or interpolating external input, which could allow injection of additional headers or response-splitting attacks. NIST SP 800-204 §3.2; NIST SP 800-53 SI-10. |
| `ps.performance.connection-reuse.missing` | warning | The script creates a new connection, session, or authenticated client on every function call rather than reusing a shared connection established during environment initialization. Repeated authentication round-trips degrade throughput and increase latency for multi-object operations. NIST SP 800-204 §4.2. |
| `ps.performance.large-payload.risk` | warning | The script fetches full objects or entire datasets when only a subset of fields or a filtered result is needed. Over-fetching wastes bandwidth, increases memory pressure, and slows connector operations. NIST SP 800-204 §4.1. |
| `ps.performance.no-early-exit` | warning | The script continues processing after reaching a definitive failure or empty result state (for example, iterating remaining items after a fatal API error, or not using `return` or `break` to short-circuit empty list paths). NIST SP 800-204 §4.2. |
| `ps.performance.string-concat.loop` | warning | String concatenation using `+=` or string interpolation is performed inside a loop to build a growing result. This creates O(n²) string copies. Prefer an array collected with `+=` on an `[System.Collections.Generic.List[string]]` or joined with `-join` after the loop. NIST SP 800-218 PW.4. |
| `ps.resilience.retry.missing` | warning | The script makes external API, database, or directory calls with no retry logic for transient failures (timeouts, HTTP 429 / 503, network drops). A single failure terminates the operation rather than allowing the connector to self-heal. NIST SP 800-53 CP-10; NIST SP 800-204 §4.3. |
| `ps.resilience.backoff.missing` | warning | Retry logic is present, but retries are fired immediately or at a fixed short interval without exponential back-off or jitter. Thundering-herd retries can amplify load on an already-stressed service. NIST SP 800-204 §4.3; NIST SP 800-53 CP-10. |
| `ps.resilience.timeout.missing` | warning | External calls have no timeout set, meaning a hung service can block the connector thread indefinitely. Set `TimeoutSec` (Invoke-RestMethod/WebRequest), `CommandTimeout` (SqlCommand), or an equivalent cancellation token. NIST SP 800-53 CP-10; NIST SP 800-204 §3.3. |
| `ps.resilience.partial-failure.unhandled` | warning | The script processes a batch or collection and does not distinguish between items that succeeded and items that failed; a single failure aborts all remaining work. Consider continuing with the next item and reporting failures separately. NIST SP 800-53 SI-17; NIST SP 800-204 §4.3. |

Notes:

- The PowerShell audit should return a readable report of violated rules, not just a summary paragraph.
- For each violated PowerShell rule, return the rule code, a short title, category, severity, score impact, evidence, and a concrete fix suggestion.
- The PowerShell quality score starts at `100` and should decrease according to the severity of the violated rules.
- Good default score impacts are: `critical=25`, `high=15`, `medium=8`, `low=4`.
- Sort PowerShell rule violations by highest score impact first when possible.
- When checking script robustness, look for meaningful logging, `try/catch` around risky operations, and `throw` or equivalent terminating behavior when failures should stop the workflow.
- For database, LDAP, cloud, and HTTP connector logic, look for injection risks caused by string concatenation or interpolation of untrusted input into queries, filters, URLs, headers, or request bodies.
- For transport security, look for weak TLS settings, certificate-validation bypasses, insecure protocol downgrades, or use of non-HTTPS endpoints for sensitive traffic.
- Also evaluate clean-code maintainability: enough useful comments, readable function size, understandable naming, and structure that can be changed or extended without excessive risk.
- These clean-code findings should normally be warnings with practical tips and suggestions for improvement rather than hard failures.
- For web request encoding: any `Invoke-WebRequest`, `Invoke-RestMethod`, or `HttpClient` call that sends or receives a body should include `; charset=utf-8` in the `Content-Type` header and should use UTF-8-aware body serialization (e.g. `[System.Text.Encoding]::UTF8.GetBytes(...)` or `ConvertTo-Json` piped with explicit encoding). Flag as `ps.quality.encoding.missing` when the script omits encoding specification and the context does not require a different charset.
- **NIST SP 800-92 logging rules** apply to the entire script. The AI should treat the rules `ps.logging.*` as a unified NIST compliance check and evaluate them together as a logging posture score. Key references:
  - **NIST SP 800-92 §2.1** — Required log record fields: timestamp (UTC), event/action type, source identity (actor), object affected, and outcome (success/failure). Every significant log message should include all five fields.
  - **NIST SP 800-92 §2.1.1 / NIST SP 800-53 AU-8** — Timestamps must be UTC-normalized and ideally in ISO 8601 format. Do not rely on local time or implicit time zones.
  - **NIST SP 800-92 §2.2 / NIST SP 800-53 AU-9** — Log output must never contain plaintext passwords, tokens, API keys, or connection strings. Detect any log call that interpolates a parameter whose name or context indicates a secret and flag as `ps.logging.secret.exposure` (error).
  - **NIST SP 800-92 §3.2 / NIST SP 800-53 AU-2** — Application-layer auditable events include: authentication attempts and outcomes, account/session operations, data create/read/update/delete actions, configuration changes, administrative actions, and significant errors or exceptions.
  - **NIST SP 800-92 §3.2 / NIST SP 800-53 AU-12** — All calls to external systems (REST, SOAP, SCIM, SQL, LDAP) must be logged with at minimum the method, sanitized target (credentials stripped from URLs), and the outcome or response code.
  - **NIST SP 800-92 §4 / NIST SP 800-53 AU-9** — Logs should be written to a centralized, protected sink (NLog, Windows Event Log) rather than to the console. `Write-Host` alone does not constitute compliant operational logging.
- For `ps.logging.secret.exposure`: inspect all logger calls, `Write-Host`, `Write-Error`, and string interpolation in log messages. Flag any message that includes a parameter whose name or context matches: `password`, `passwd`, `secret`, `token`, `apikey`, `api_key`, `clientsecret`, `accesskey`, `privatekey`, `credential`, or similar. Raise as **error** severity because secret leakage into logs is a direct data exposure risk.
- For `ps.logging.structured.missing`: flag `Write-Host`, `Write-Output`, or `Write-Verbose` used as the **primary** logging mechanism where NLog / `Get-Logger` calls are absent or sparse. If NLog is already used for all significant events, suppress this rule even if a few `Write-Host` lines exist for debug or test output.
- For `ps.logging.external-calls.missing`: check that every `Invoke-WebRequest`, `Invoke-RestMethod`, `SqlCommand.ExecuteReader`, LDAP search, or equivalent call has a `$logger.Info(...)` or equivalent call immediately before or after it that records the target and outcome. A bare `try { Invoke-RestMethod ... } catch { }` with no log is a violation.
- For `ps.logging.crud-operations.missing`: check that `Insert`, `Update`, and `Delete` PowerShell functions each log the entity type, the primary identifier (when available from parameters), and outcome before returning. Read (List/Get) functions should log at entry and at completion with record count or entity ID.
- Score impact guidance for NIST logging rules: `ps.logging.secret.exposure` = 25 (critical); `ps.logging.auth-events.missing` = 10 (high); `ps.logging.crud-operations.missing` = 8; `ps.logging.external-calls.missing` = 8; `ps.logging.error-context.insufficient` = 8; `ps.logging.structured.missing` = 6; `ps.logging.timestamp.missing` = 6; `ps.logging.outcome.missing` = 6; `ps.logging.actor.missing` = 4; `ps.logging.event-type.missing` = 4; `ps.logging.function-boundary.missing` = 4.
- **NIST SP 800-53 / SP 800-218 security rules** — Apply the `ps.security.*` extended rules as a security posture check. Key detection guidance:
  - For `ps.security.least-privilege.missing` (NIST SP 800-53 AC-6): check whether credentials or tokens used in the script are scoped to read-only or minimum-write permissions for the operation, or whether admin/global credentials are used where a narrower scope would suffice.
  - For `ps.security.input-validation.missing` (NIST SP 800-218 PW.5 / SP 800-53 SI-10): inspect any parameter whose value flows into a query, URL, header, or command body. If there is no `[ValidateNotNullOrEmpty()]`, `[ValidatePattern(...)]`, length check, or allowlist check before use, flag it. Focus on parameters that arrive from external sources such as object IDs, search strings, or user-provided paths.
  - For `ps.security.credential-rotation.missing` (NIST SP 800-53 IA-5 / SP 800-63B §5.2.3): look for tokens stored in global variables or passed as parameters with no refresh, no expiry check, and no logic to re-authenticate on a 401/403 response. Long-lived secrets without rotation increase exposure window.
  - For `ps.security.timeout.missing` (NIST SP 800-53 SC-5 / SP 800-204 §3.3): check every `Invoke-WebRequest`, `Invoke-RestMethod`, `SqlCommand`, and `HttpClient` call for a `TimeoutSec`, `CommandTimeout`, or equivalent. Absence is a vulnerability because it allows slow or hostile services to exhaust connection threads.
  - For `ps.security.error-disclosure.risk` (NIST SP 800-53 SI-11 / SP 800-218 RV.1): check `catch` blocks that rethrow or return `$_.Exception.Message` or `$_.Exception.ToString()` directly to callers. Stack traces, file paths, and schema names in error messages are information disclosure.
  - For `ps.security.insecure-deserialization` (NIST SP 800-218 PW.6 / SP 800-53 SI-10): any `ConvertFrom-Json`, `[xml]`, `XmlDocument`, or `Select-Xml` applied directly to raw HTTP response bodies or external strings without prior size/schema validation is a finding.
  - For `ps.security.header-injection.risk` (NIST SP 800-204 §3.2): check for `$headers["X-Something"] = $param` where `$param` is an external value. Newlines in header values (`\r\n`) break HTTP framing. Validate or strip newlines before header insertion.
  - Score impact guidance for `ps.security.*` extended rules: `ps.security.insecure-deserialization` = 15 (high); `ps.security.tls-weakened` = 25 (critical); `ps.security.sql-injection` = 25 (critical); `ps.security.ldap-injection` = 25 (critical); `ps.security.hardcoded.secret` = 25 (critical); `ps.security.timeout.missing` = 10 (high); `ps.security.least-privilege.missing` = 10 (high); `ps.security.credential-rotation.missing` = 8; `ps.security.input-validation.missing` = 8; `ps.security.error-disclosure.risk` = 6; `ps.security.header-injection.risk` = 8; `ps.security.open-redirect.risk` = 8.
- **Performance and resilience rules** — Apply the `ps.performance.*` and `ps.resilience.*` rules as operational efficiency checks. Key detection guidance:
  - For `ps.performance.connection-reuse.missing` (NIST SP 800-204 §4.2): check whether the connector creates a new authenticated session or client per function call rather than reusing a connection set up in `EnvironmentInitialization`. Repeated OAuth round-trips per entity CRUD operation are a common connector anti-pattern.
  - For `ps.performance.large-payload.risk` (NIST SP 800-204 §4.1): check whether `ListingCommand` functions request all fields when only a subset is used, or fetch every page of results when only the first match is needed. Look for absent `$select`, `$top`, or field-filter parameters on API calls.
  - For `ps.performance.string-concat.loop` (NIST SP 800-218 PW.4): find `+=` used on a `[string]` inside a `foreach`, `for`, or `while` loop. This is O(n²) copying in PowerShell and should be replaced with a list or `-join`.
  - For `ps.resilience.retry.missing` (NIST SP 800-53 CP-10 / SP 800-204 §4.3): any external call block (`try { Invoke-RestMethod ... } catch { throw }`) with no sleep-and-retry pattern for transient errors is a finding. Idempotent GET and safe retries on 429/503/timeout are expected for production connectors.
  - For `ps.resilience.backoff.missing` (NIST SP 800-204 §4.3): if retry logic exists but uses `Start-Sleep -Seconds 1` in a fixed loop, flag it. The pattern should use `Start-Sleep -Seconds ([math]::Pow(2, $attempt))` with optional jitter.
  - For `ps.resilience.partial-failure.unhandled` (NIST SP 800-53 SI-17): check `foreach` loops that process entity batches. If the first failure throws out of the loop without a per-item `try/catch`, the remaining items are silently abandoned.
  - Score impact guidance for performance and resilience rules: `ps.resilience.retry.missing` = 10 (high); `ps.resilience.backoff.missing` = 6; `ps.resilience.timeout.missing` = 10 (high); `ps.resilience.partial-failure.unhandled` = 8; `ps.performance.connection-reuse.missing` = 8; `ps.performance.large-payload.risk` = 6; `ps.performance.no-early-exit` = 4; `ps.performance.string-concat.loop` = 4.

### Hardcoded Secret Rules

These checks are AI-driven and should scan both the XML and the PowerShell file, including comments, examples, disabled code, and inline string literals.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `security.hardcoded.password` | error | A hardcoded password, passphrase, client secret, token secret, or similarly sensitive credential appears in XML or PowerShell. |
| `security.hardcoded.key` | error | A hardcoded API key, private key material, bearer token, signing secret, certificate blob, or similar secret appears in XML or PowerShell. |
| `security.hardcoded.connection-string` | error | A hardcoded connection string or DSN with embedded credentials or sensitive endpoints appears in XML or PowerShell. |
| `security.hardcoded.secret.comment` | error | A comment appears to contain a real hardcoded password, key, token, connection string, or other sensitive value. |
| `security.hardcoded.secret.example` | warning | A value looks secret-like but may be an example, placeholder, or dummy sample rather than a live credential. |

Notes:

- Inspect XML attributes, XML element text, PowerShell assignments, hashtables, function defaults, here-strings, and comments.
- Inspect both active code and comments because credentials are sometimes left in disabled blocks or explanatory notes.
- Distinguish likely real secrets from obvious placeholders such as `changeme`, `your-api-key`, `<password>`, or `example-token`; uncertain cases should normally be warnings rather than errors.
- If a connection string is present without obvious credentials but still exposes sensitive infrastructure details, prefer a warning unless the risk is clearly severe.

### Reference XML Comparison Rules

These only run when both of these are true:

- schema JSON was uploaded
- at least one PowerShell function was parsed

The validator generates a reference XML from the same upload builder logic and compares it against the uploaded XML.

| Code | Default Severity | What It Checks |
| --- | --- | --- |
| `reference.class.missing` | warning | The generated reference XML expects a class that is missing from the uploaded XML. |
| `reference.class.extra` | info | The uploaded XML contains a class that does not appear in the generated reference XML. |
| `reference.connection-parameter.missing` | warning | The generated reference XML expects a connection parameter missing from the uploaded XML. |
| `reference.connection-parameter.extra` | info | The uploaded XML contains a connection parameter that does not appear in the generated reference XML. |

## Summary Object Returned To The UI

The UI depends on the `summary` returned by the AI validator route.

Current fields:

- `totalFunctions`
- `globalFunctions`
- `helperFunctions`
- `xmlClasses`
- `customCommands`
- `predefinedCommands`
- `inferredConnectionParameters`
- `actualConnectionParameters`
- `expectedEntities`

If you change rule logic, there is a good chance you will also want to change this summary because the right-hand sidebar on `/XML-Validator` uses it directly.

## Where To Edit Things

### If you want to change generic XML/schema checks

Edit:

- `app/utils/validation.ts`

Typical changes:

- relax XML hygiene warnings
- change how ReturnBind checks work
- change duplicate-name behavior
- remove or tighten schema property checks

### If you want to change PowerShell signature logic

Edit:

- `app/XML-Validator/validation.ts`
- `lib/ps-parse.ts`

Typical changes:

- change which PowerShell naming patterns imply entity operations
- stop requiring `global:` functions
- change CRUD verb mapping
- change parameter inference
- change type comparison logic

### If you want to change the generated reference XML comparison

Edit:

- `app/XML-Validator/validation.ts`
- `lib/uploadPwxml.ts`

Typical changes:

- change how the reference XML is built
- disable reference comparisons
- compare more XML sections than classes and connection parameters

### If you want to change AI behavior

Edit:

- `app/api/ai/xml-validator/route.ts`

That route does not create rules. It only turns the deterministic findings into remediation guidance.

## Good First Improvements

If you want to make this validator easier to evolve, these are the best first refactors:

1. Move rule metadata into a central registry with code, default severity, description, and toggle state.
2. Allow severity overrides per rule code instead of hardcoding them inline.
3. Make root-element expectations configurable.
4. Make the global-function requirement configurable.
5. Externalize the CRUD verb mapping so non-standard naming can be supported.
6. Add allow-lists for intentional XML/PowerShell naming mismatches.
7. Improve return-shape inference beyond simple `[pscustomobject] @{ ... }` assignments.

## Related Files

- `app/XML-Validator/page.tsx`
- `app/XML-Validator/validation.ts`
- `app/api/ai/xml-validator/route.ts`
- `app/utils/validation.ts`
- `app/utils/normalizeSchema.ts`
- `lib/ps-parse.ts`
- `lib/uploadPwxml.ts`
