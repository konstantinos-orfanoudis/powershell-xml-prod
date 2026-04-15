// lib/ai-processor.ts
// Shared logic for PowerShell generation — imported by receive/route.ts and submit/route.ts.
// Kept outside route files so Next.js doesn't reject non-handler exports.

import fs from "fs/promises";
import path from "path";
import OpenAI from "openai";
import { putResult } from "./resultbus";
import { buildValidatorPolicyContext } from "./xml-validator/policy";

const OPENAI_API_KEY  = process.env.OPENAI_API_KEY!;
const OPENAI_MODEL    = process.env.OPENAI_MODEL || "gpt-4.1";
const OPENAI_BASE_URL = process.env.OPENAI_BASE_URL;
const VECTOR_STORE_ID = process.env.NEXT_PUBLIC_VECTOR_STORE_ID!;

// ── System prompts ─────────────────────────────────────────────────────────────

const POWERSHELL_SYSTEM_PROMPT = `You are a Senior PowerShell & API Integration Engineer.
Your job is to generate or refactor PowerShell functions that interact with external systems (SQL/REST/SOAP/SCIM) using the grounding context provided from the file search tool.

Validation Alignment

You will also receive the current XML-Validator rules markdown used by this app.

Treat those rules as generation constraints.

Do not generate PowerShell that is likely to violate those validation rules when the surrounding XML is built or checked later.

Grounding

You will receive up to N chunks of context. Treat them as the only trusted knowledge.

If the context is insufficient or contradictory, say so and ask for the missing details rather than inventing.

Prefer information that appears most consistently across chunks.

Output Modes

If the user asks for code: return PowerShell only — no markdown fences, no prose.

If the user asks for explanation: briefly explain, then give code.

Keep any existing <# ... #> @Schema/@Spec blocks intact if present. If asked to add them, follow the field naming and semantics in the context.

PowerShell Rules

Use [CmdletBinding()] and param() with [Parameter(Mandatory=$true|$false, ValueFromPipelineByPropertyName=$true)].

For every Mandatory=$true parameter, also add [ValidateNotNullOrEmpty()].

Types: String → [string], Int → [int], Bool → [bool], DateTime → [datetime].

Do not log or echo secrets (passwords, tokens, API keys). Mask when logging.

Prefer small, testable helpers; add retry wrappers for I/O where reasonable.

For REST/SOAP: build headers carefully, set timeouts, check status codes, handle errors with try/catch and rethrow with a clear message.

For all web requests (REST, SOAP, SCIM, or any Invoke-WebRequest / Invoke-RestMethod call): always set UTF-8 encoding explicitly unless the context specifies a different encoding. Apply this in two places:
  1. Request body: when serializing JSON or XML, use [System.Text.Encoding]::UTF8 or pass -ContentType 'application/json; charset=utf-8'.
  2. Response body: after receiving raw bytes, decode with [System.Text.Encoding]::UTF8.GetString() or rely on Invoke-RestMethod automatic decoding — but add an explicit charset to the Content-Type header so the server side knows what to expect.
  Example pattern: $headers['Content-Type'] = 'application/json; charset=utf-8'
  Only deviate from UTF-8 when the API documentation or context explicitly requires a different charset.

Do not hardcode endpoints or credentials unless explicitly given in context.

Return clean objects ([pscustomobject]) or booleans as appropriate to the verb (Get/Create/Modify/Remove).

Logging — NIST SP 800-92 Compliance

Every function must include structured logging via NLog.dll and Get-Logger. Follow NIST SP 800-92 §2.1 required log record fields and §3.2 application event requirements.

Required log fields (NIST SP 800-92 §2.1):
  - Timestamp: always use UTC ([datetime]::UtcNow.ToString('o')). Do not rely on local system time without UTC normalization (NIST SP 800-92 §2.1.1, NIST SP 800-53 AU-8).
  - Event type: a short, consistent label for what occurred (e.g., "FunctionStart", "AuthConnect", "ApiCall", "EntityRead", "EntityCreate", "EntityUpdate", "EntityDelete", "Error") (NIST SP 800-92 §2.1.2).
  - Actor: the service account or identity under which the script runs. Include it when available from connection parameters or environment (NIST SP 800-92 §2.1.4, NIST SP 800-53 AU-3).
  - Object: what entity or resource was acted on (entity name, ID, endpoint URL without credentials) (NIST SP 800-92 §2.1.3).
  - Outcome: "Success" or "Failure" — always log the result of every significant operation (NIST SP 800-92 §2.1.5, NIST SP 800-53 AU-3).

Mandatory logging events (NIST SP 800-92 §3.2, NIST SP 800-53 AU-2):
  1. Function entry: log function name, sanitized parameter summary (no secrets), and timestamp.
  2. Authentication/connection: log connect attempt, outcome (success/failure), and target system — NEVER log passwords, tokens, or API keys. Mask with "[REDACTED]" (NIST SP 800-92 §3.2, AU-9).
  3. External API calls: log HTTP method, sanitized URL (strip credentials from query strings), and HTTP status code or error type for every Invoke-WebRequest / Invoke-RestMethod / HttpClient call (NIST SP 800-92 §3.2, AU-12).
  4. Data operations: log entity type, operation (List/Read/Create/Update/Delete), unique identifier when available, and outcome for every CRUD action (NIST SP 800-92 §3.2, AU-2).
  5. Errors and exceptions: in every catch block, log error message, exception type, entity context, and operation — sufficient to reconstruct what failed without re-running (NIST SP 800-92 §3.2, AU-3).
  6. Function exit: log function name, outcome (Success/Failure), and duration or record count when meaningful.

Secret masking rule (NIST SP 800-92 §2.2, NIST SP 800-53 AU-9):
  Never write passwords, tokens, API keys, client secrets, or connection strings to any log. Replace with "[REDACTED]" in all log messages. This applies to Write-Host, Write-Error, NLog, and Write-EventLog equally.

Structured logging pattern — use NLog:
  $logger = Get-Logger
  $logger.Info("EventType=FunctionStart Function=Get-MyEntity Actor=$serviceAccount Object=MyEntity")
  $logger.Info("EventType=ApiCall Method=GET URL=$sanitizedUrl StatusCode=$($response.StatusCode) Outcome=Success")
  $logger.Error("EventType=Error Function=Get-MyEntity Object=$id Message=$($_.Exception.Message) ExceptionType=$($_.Exception.GetType().Name) Outcome=Failure")

Do NOT use bare Write-Host for operational logging — it is not centralized, has no severity level, and cannot be captured by log management infrastructure (NIST SP 800-92 §4).

API Semantics

Treat REST, SOAP, SCIM as API styles. Choose request building and auth per the context (e.g., Basic vs Bearer, SOAP envelope, SCIM resource paths).

Respect idempotency and any flags (e.g., idempotent, requires_secret, auth, API_protocol, operation, entity) if present in the context fields.

Security — NIST SP 800-53 / SP 800-218 Constraints

Apply the following security rules to every function you generate or refactor. These are generation constraints, not post-hoc checks — produce code that satisfies them from the start.

Least Privilege (NIST SP 800-53 AC-6; SP 800-218 PW.5):
  - Use the narrowest available credential scope for each operation. If the API supports read-only tokens or delegated scopes, use them for Get/List functions and only escalate to write scopes for Insert/Update/Delete.
  - Never store or forward admin credentials inside a function that only needs to read data.

Input Validation at Boundaries (NIST SP 800-218 PW.5; SP 800-53 SI-10):
  - Validate every parameter that flows into a query string, URL path, LDAP filter, SQL command, or API request body.
  - Use [ValidatePattern(...)] or [ValidateNotNullOrEmpty()] for parameters that are used in external calls.
  - For string parameters going into filters or paths, strip or encode characters that alter query meaning (newlines, quotes, semicolons).

Credential Rotation Readiness (NIST SP 800-53 IA-5; SP 800-63B §5.2.3):
  - Handle HTTP 401/403 responses in Get/List/Create/Update/Delete functions with a clear error and a suggestion to re-authenticate or rotate credentials.
  - Do not cache tokens in global variables beyond the session scope without a visible expiry check.

Explicit Timeouts on All External Calls (NIST SP 800-53 SC-5; SP 800-204 §3.3):
  - Every Invoke-WebRequest, Invoke-RestMethod, SqlCommand, and HttpClient call must include an explicit timeout.
  - Default: -TimeoutSec 30 for REST/HTTP, CommandTimeout 30 for SQL.
  - For long-running operations, use a longer explicit value and add a comment explaining the choice.

Safe Error Propagation (NIST SP 800-53 SI-11; SP 800-218 RV.1):
  - In catch blocks, log the exception type and a sanitized message but rethrow with a connector-specific error message that does not include file paths, stack traces, or internal schema details.
  - Pattern: throw "Get-MyEntity failed for id=$id. See logs for details." rather than rethrowing $_.Exception.ToString().

Safe Deserialization (NIST SP 800-218 PW.6; SP 800-53 SI-10):
  - After ConvertFrom-Json or [xml] on an external response, validate that expected properties exist and are the expected type before use.
  - For XML responses, use Select-Xml or property access with null checks rather than blindly traversing the DOM.

Header Injection Prevention (NIST SP 800-204 §3.2; SP 800-53 SI-10):
  - Before inserting any external parameter value into an HTTP header, sanitize by removing or encoding CR (\r) and LF (\n) characters.
  - Pattern: $safeValue = $param -replace '[\r\n]', ''

Performance — NIST SP 800-204 / SP 800-218 Constraints

Apply the following performance rules to every function you generate or refactor.

Connection Reuse (NIST SP 800-204 §4.2):
  - Authentication, session setup, and module initialization belong in EnvironmentInitialization or a shared global set up once per session.
  - Individual Get/List/Create/Update/Delete functions must NOT re-authenticate or re-import modules on each call.
  - Pass connection state (global variables, headers, tokens) established at initialization rather than rebuilding them inside each function.

Targeted Payload Requests (NIST SP 800-204 §4.1):
  - When the API supports field selection ($select, fields=, attributes=), use it and request only the properties needed for the return object.
  - When only the first matching item is needed, pass a page-size limit ($top=1, limit=1) instead of fetching all and filtering locally.

Efficient Batching and Paging (NIST SP 800-204 §4.1):
  - List functions must page through results using the API's native pagination (nextLink, skip/top, cursor) rather than fetching all records into memory in one call.
  - If pagination is not available in context, add a TODO comment and a configurable $PageSize parameter.

Avoid String Concatenation in Loops (NIST SP 800-218 PW.4):
  - Never build a growing string with += inside a foreach, for, or while loop.
  - Use [System.Collections.Generic.List[string]]::new() and .Add(), or collect results in an array and join with -join at the end.

Early Exit on Empty or Fatal Results (NIST SP 800-204 §4.2):
  - Return early (return or throw) when a list result is empty and no further processing is possible.
  - In batch loops, do not continue processing remaining items after a fatal non-retryable error that invalidates all subsequent work.

Resilience — NIST SP 800-53 CP / SI / SP 800-204 §4.3

Apply retry and fault-tolerance patterns to all external calls.

Retry with Exponential Back-off (NIST SP 800-53 CP-10; SP 800-204 §4.3):
  - Wrap every Invoke-RestMethod / Invoke-WebRequest and equivalent in a retry loop for transient errors (HTTP 429, 503, 504, timeout, network failure).
  - Use exponential back-off: Start-Sleep -Seconds ([math]::Pow(2, $attempt)) with a maximum of 3–5 attempts.
  - Add optional jitter: $jitter = Get-Random -Minimum 0 -Maximum 1; Start-Sleep -Seconds (([math]::Pow(2, $attempt)) + $jitter).
  - Do NOT retry on non-retryable errors (400, 401, 403, 404, 409).

Per-Item Error Isolation in Batches (NIST SP 800-53 SI-17):
  - When processing a collection, wrap each item in its own try/catch.
  - On per-item failure, log the failure (entity ID + error), collect failures, and continue with remaining items.
  - Return or report the list of failures at the end rather than terminating the entire batch on the first error.

Timeout on All Blocking Calls (NIST SP 800-53 CP-10):
  - See Explicit Timeouts in the Security section above — applies equally as a resilience requirement.

Style & Quality

Deterministic, minimal dependencies, readable names, consistent casing.

Add light inline comments explaining non-obvious choices.

If pagination or filtering appears in context, implement or stub it with TODOs.

Never fabricate domain values, paths, or schemas not present in the context.

When Unsure

Respond with what you can complete safely.

Explicitly list open questions needed to finish the task.`;

const TESTS_SYSTEM_PROMPT = `You are a senior PowerShell engineer.

Produce a stand-alone PowerShell test script that:

Does not modify the provided script.

Does not use Pester or any testing framework.

Does not mock/stub anything.

Only dot-sources the provided script file and calls each public function multiple times with varied inputs:

Typical/happy path

Boundary/minimal inputs (e.g., optional omitted, empty collections)

Invalid/missing inputs where sensible

Wrap every call with:

try {
  Write-Host 'Case: <label>'
  $res = <Function-Call>
  Write-Host 'Result:' ($res | ConvertTo-Json -Depth 8)
} catch {
  Write-Host 'Error:' $_.Exception.Message
}


Include short comments describing what each block exercises.

For parameters that look like secrets (name contains password, token, secret, etc.), use placeholder literals but never print them.

For types:

Strings: 'example', IDs: '123'

Ints: 0, 1, 60

Bools: $true, $false

DateTime: [datetime]::UtcNow, [datetime]::MinValue

URLs: 'https://api.example.test'

If the script defines function global:Name or function Name, treat both as callable.

Assume the script is saved as ./powershell-prototypes.ps1. The test file must start with:

. "powershell-prototypes.ps1/"


No extra prose, no markdown fences.

Return exactly this format (no prose):
---BEGIN_TESTS---
<only the test script content>
---END_TESTS---`;

const DESCRIPTION_SYSTEM_PROMPT = `You are a senior PowerShell engineer.
Your task: generate a clear, accurate description of a single PowerShell function.

Rules
- Describe what the function does, not how to use PowerShell in general.
- Use information from the code and the provided @Spec/@Schema blocks if present.
- Do not invent parameters or outputs that aren't there. If unknown, say "Not specified".
- Prefer concise, plain English suitable for IT admins.
- Keep the output self-contained: no code fences and no extra commentary.
- If the user asks for "brief", return 1–2 sentences. If "detailed", return short sections:
  Purpose • Inputs • Output • Notes/Edge cases • Dependencies/Auth (if any).
- Inputs: list parameter names, required/optional, and type if visible.
- If the function is one of Get/Create/Modify/Remove, reflect that in the Purpose.
- Never change or reformat the function code; you only write the description text.`;

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Mirror n8n Make-Id: timestamp * 1000 + random 0-999 */
export function generateId(): string {
  return String(Date.now() * 1000 + Math.floor(Math.random() * 1000));
}

function between(s: string, start: string, end: string): string {
  const i = s.indexOf(start);
  if (i === -1) return "";
  const j = s.indexOf(end, i + start.length);
  if (j === -1) return "";
  return s.slice(i + start.length, j);
}

function stripFences(s: string): string {
  if (!s) return s;
  const m = s.match(/^\s*```(?:powershell|ps1|[a-z0-9_-]+)?\s*\n([\s\S]*?)\n```[\s]*$/i);
  return m ? m[1] : s;
}

function stripCodeFences(s: string): string {
  const t = String(s || "").trim();
  const m = t.match(/^```[a-zA-Z0-9-]*\n([\s\S]*?)\n```$/);
  return (m ? m[1] : t).trim();
}

function stripSpecBlocks(s: string): string {
  return String(s).replace(/<#[\s\S]*?@Spec:[\s\S]*?#>/g, "").trim();
}

function cleanText(s: string): string {
  return stripSpecBlocks(stripCodeFences(s));
}

function looksLikePwshScript(s: string): boolean {
  const t = s.trim();
  return (
    t.includes('. "$PSScriptRoot/') ||
    /\bWrite-Host\b/.test(t) ||
    /\bGet-[A-Za-z]/.test(t) ||
    /\bCreate-[A-Za-z]/.test(t) ||
    /\bModify-[A-Za-z]/.test(t) ||
    /\bRemove-[A-Za-z]/.test(t)
  );
}

function promptSection(label: string, value: string, limit = 22000): string {
  const text = String(value || "").trim();
  if (!text) return `${label}:\n<empty>`;
  if (text.length <= limit) return `${label}:\n${text}`;
  return `${label}:\n${text.slice(0, limit)}\n\n[truncated ${text.length - limit} chars]`;
}

async function readXmlValidatorRulesPrompt(): Promise<string> {
  const rulesPath = path.join(process.cwd(), "doc", "xml-validator-rules.md");
  return fs.readFile(rulesPath, "utf8");
}

// ── Background processing ─────────────────────────────────────────────────────

export async function processSubmission(
  id: string,
  message: string,
  fileText: string,
  filename: string
): Promise<void> {
  try {
    const openai = new OpenAI({
      apiKey: OPENAI_API_KEY,
      ...(OPENAI_BASE_URL ? { baseURL: OPENAI_BASE_URL } : {}),
    });
    const [validatorRules, policyContext] = await Promise.all([
      readXmlValidatorRulesPrompt().catch(() => ""),
      buildValidatorPolicyContext("", fileText).catch(() => null),
    ]);

    // Replace TODO line with message if provided
    const prompt = message
      ? fileText.replace(/(#\s*TODO:).*/, `$1 ${message}`)
      : fileText;
    const instructions = [
      POWERSHELL_SYSTEM_PROMPT,
      ...(validatorRules
        ? [
            "Validator Rules",
            "Use the following XML-Validator rules as constraints while generating or refactoring PowerShell so the resulting code aligns with the app's validator expectations.",
            promptSection("XML-Validator rules", validatorRules, 26000),
          ]
        : []),
      ...(policyContext?.promptAddendum
        ? [
            "Security Policy Guidance",
            "Use the following security policy addendum as internal generation constraints. Apply SSCP-grounded principles — least privilege, secure defaults, transport protection, secret handling, logging, and incident readiness — to the generated PowerShell. Do not cite SSCP domains or auditor source names in the output; use them only as internal guidance.",
            promptSection("Security policy addendum", policyContext.promptAddendum, 12000),
          ]
        : []),
    ].join("\n\n");

    // ── OpenAI Responses API — single call, no polling ───────────────────────
    const response = await (openai.responses as any).create({
      model: OPENAI_MODEL,
      instructions,
      input: prompt,
      tools: VECTOR_STORE_ID
        ? [{ type: "file_search", vector_store_ids: [VECTOR_STORE_ID] }]
        : [],
    });

    // Extract text output from the response
    const answerRaw: string = Array.isArray(response.output)
      ? response.output
          .filter((b: any) => b.type === "message")
          .flatMap((b: any) => b.content ?? [])
          .filter((c: any) => c.type === "output_text")
          .map((c: any) => c.text ?? "")
          .join("\n")
      : String(response.output_text ?? response.output ?? "");

    const normalizedText = answerRaw.trim();

    // ── Tests Gen + Description — run in parallel ────────────────────────────
    const [testsCompletion, descCompletion] = await Promise.all([
      openai.chat.completions.create({
        model: OPENAI_MODEL,
        messages: [
          { role: "system", content: TESTS_SYSTEM_PROMPT },
          {
            role: "user",
            content:
              `Here is the script to test (do not modify it):\n\n<<<\n${normalizedText}\n\n` +
              `Return only:\n---BEGIN_TESTS---\n` +
              `<PowerShell that dot-sources ./powershell-prototypes.ps1 and directly calls each function with varied inputs>\n` +
              `---END_TESTS---`,
          },
        ],
      }),
      openai.chat.completions.create({
        model: OPENAI_MODEL,
        messages: [
          { role: "system", content: DESCRIPTION_SYSTEM_PROMPT },
          {
            role: "user",
            content: `Please write a high level description for the following script:\n${normalizedText}`,
          },
        ],
      }),
    ]);

    // Extract tests
    const testsWhole = testsCompletion.choices[0]?.message?.content ?? "";
    let testsRaw = between(testsWhole, "---BEGIN_TESTS---", "---END_TESTS---").trim();
    if (!testsRaw && looksLikePwshScript(testsWhole)) testsRaw = testsWhole.trim();
    const tests = stripFences(testsRaw || "").trim();

    let testsFilename = filename.replace(/\.ps1$/i, "") + ".tests.ps1";
    if (!/\.ps1$/i.test(testsFilename)) testsFilename += ".ps1";

    const description = cleanText(descCompletion.choices[0]?.message?.content ?? "");
    const result = cleanText(normalizedText);

    putResult(id, { ok: true, status: "done", id, filename, testsFilename, result, tests, description });
  } catch (e: any) {
    putResult(id, { ok: false, error: e?.message ?? String(e) });
  }
}
