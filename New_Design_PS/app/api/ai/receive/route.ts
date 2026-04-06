// app/api/ai/receive/route.ts
// Native replacement for the n8n "Powershell intragen" submit branch.
// Flow: receive { message, fileText } → respond pending → background:
//   OpenAI Responses API (PS generation) → Tests Gen → Description → putResult
// Companion: result/route.ts reads the result via waitForResult.

import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";
import { putResult } from "../../../../lib/resultbus";

export const runtime = "nodejs";

const OPENAI_API_KEY    = process.env.OPENAI_API_KEY!;
const OPENAI_MODEL      = process.env.OPENAI_MODEL || "gpt-4.1";
const OPENAI_BASE_URL   = process.env.OPENAI_BASE_URL;
const VECTOR_STORE_ID   = process.env.NEXT_PUBLIC_VECTOR_STORE_ID!;

// ── System prompts ────────────────────────────────────────────────────────────

const POWERSHELL_SYSTEM_PROMPT = `You are a Senior PowerShell & API Integration Engineer.
Your job is to generate or refactor PowerShell functions that interact with external systems (SQL/REST/SOAP/SCIM) using the grounding context provided from the file search tool.

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

Do not hardcode endpoints or credentials unless explicitly given in context.

Return clean objects ([pscustomobject]) or booleans as appropriate to the verb (Get/Create/Modify/Remove).

Always include logging using Nlog.dll and Get-Logger. Use Logging for start and end of functions and for the intermediate steps.

API Semantics

Treat REST, SOAP, SCIM as API styles. Choose request building and auth per the context (e.g., Basic vs Bearer, SOAP envelope, SCIM resource paths).

Respect idempotency and any flags (e.g., idempotent, requires_secret, auth, API_protocol, operation, entity) if present in the context fields.

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

// ── Helpers ──────────────────────────────────────────────────────────────────

function bad(msg: string, status = 400) {
  return NextResponse.json({ ok: false, error: msg }, { status });
}

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

    // Mirror n8n "Extract message and filetext": replace TODO line with message
    const prompt = message
      ? fileText.replace(/(#\s*TODO:).*/, `$1 ${message}`)
      : fileText;

    // ── OpenAI Responses API — single call, no polling ───────────────────────
    const response = await (openai.responses as any).create({
      model: OPENAI_MODEL,
      instructions: POWERSHELL_SYSTEM_PROMPT,
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

    // ── Tests Gen + Description Agent — run in parallel ──────────────────────

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

    // Mirror n8n "normalize tests": extract between markers, strip fences
    const testsWhole = testsCompletion.choices[0]?.message?.content ?? "";
    let testsRaw = between(testsWhole, "---BEGIN_TESTS---", "---END_TESTS---").trim();
    if (!testsRaw && looksLikePwshScript(testsWhole)) testsRaw = testsWhole.trim();
    const tests = stripFences(testsRaw || "").trim();

    let testsFilename = filename.replace(/\.ps1$/i, "") + ".tests.ps1";
    if (!/\.ps1$/i.test(testsFilename)) testsFilename += ".ps1";

    const description = cleanText(descCompletion.choices[0]?.message?.content ?? "");

    // ── Normalize and store (mirrors n8n "Prepare response" + "Upsert result") ─

    const result = cleanText(normalizedText);

    putResult(id, {
      ok: true,
      status: "done",
      id,
      filename,
      testsFilename,
      result,
      tests,
      description,
    });
  } catch (e: any) {
    putResult(id, { ok: false, error: e?.message ?? String(e) });
  }
}

// ── Route handler ─────────────────────────────────────────────────────────────

export async function POST(req: NextRequest) {
  if (!OPENAI_API_KEY) return bad("server missing OPENAI_API_KEY", 500);

  let message  = "";
  let fileText = "";
  let filename = "powershell-prototypes.ps1";

  const ct = req.headers.get("content-type") ?? "";
  if (ct.includes("application/json")) {
    // Primary format used by the PS tool: { message, fileText, filename? }
    let body: any;
    try { body = await req.json(); } catch { return bad("invalid JSON body"); }
    message  = String(body.message  ?? "");
    fileText = String(body.fileText ?? "");
    filename = String(body.filename ?? filename);
  } else {
    // Backward-compat: plain PS text in body + optional x-filename header
    fileText = await req.text();
    filename = req.headers.get("x-filename") ?? filename;
  }

  // Mirror n8n Make-Id → fast response with id (202)
  const id = generateId();
  setImmediate(() => { void processSubmission(id, message, fileText, filename); });

  return NextResponse.json({ ok: true, id, status: "pending" }, { status: 202 });
}
