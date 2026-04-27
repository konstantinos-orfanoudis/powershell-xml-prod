// app/api/ai/submitFile/route.new.ts
// Native replacement for the n8n "schemaJsonGenerator Intragen" workflow.
// Flow: receive file → parse (JSON/PDF/XML) → OpenAI → putResult(requestId, result)
// The companion resultFiles/route.new.ts reads the result via waitForResult.

import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";
import { extractPdfText } from "../../../../lib/pdf/extractFromPdf";
import { putResult } from "../../../../lib/resultbus";
import { fileNameToEntityHint } from "../../../../lib/schemaEntityNames";

export const runtime = "nodejs";

const OPENAI_API_KEY = process.env.OPENAI_API_KEY!;
const OPENAI_BASE_URL = process.env.OPENAI_BASE_URL; // optional — set to use Groq, Gemini, Ollama, etc.
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";

// Exact system prompt from the n8n AI Agent node
const SYSTEM_PROMPT = `You are a schema extractor. From the inputs I provide (samples, specs, or a precomputed attribute inventory), produce ONE JSON object that strictly matches this contract:

{
  "name": "Connector",
  "version": "1.0.0",
  "entities": [
    {
      "name": "EntityName",
      "attributes": [
        { "name": "attribute_name", "type": "String|Int|Bool|Datetime", "MultiValue": true|false, "IsKey": true|false }
      ]
    }
  ]
}

CRITICAL RULES

1) Output format
- Return JSON ONLY, no markdown, no comments, no prose.
- Use the exact property names and casing above. Use "IsKey" (capital I, K). Never include "isKey".
- Sort entities by name ascending; within each entity, sort attributes by name ascending.

2) Coverage (do not drop fields)
- Include ALL attributes found or implied by the inputs. If I provide \`requiredEntities\` (a lower-bound inventory of {name, attributes[]}), your result MUST include at least those attributes (and may add more from the samples/specs).
- If the same attribute appears with different types across examples, choose the most general according to typing rules (see §3). Never omit a conflicting attribute—resolve it.

3) Typing rules
- true/false → Bool
- Pure integers (no decimals, no scientific notation) → Int
- ISO-8601/RFC-3339 date/time strings (e.g., 2021-05-03, 2021-05-03T12:34:56Z, 2021-05-03T12:34:56+02:00 and all other formats for dates) → DateTime
- Everything else (IDs, GUIDs, free text, enums, decimals/floats, mixed numeric) → String

4) Arrays and nesting
- Arrays of scalars → keep ONE attribute on the parent with MultiValue:true and scalar type from §3. Never use type:"Array".
- Arrays of objects → model as a relationship:
  a) Create a Child entity named from the array's item shape (TitleCase, singular).
  b) Create an Assignment entity named "{Parent}Has{Child}" containing the key fields referenced from the Parent and Child; both are IsKey:true in the Assignment.
  c) Do NOT keep the list attribute itself on the parent.
- Nested 1:1 objects → flatten into the parent using snake_case "{nested}_{field}" for scalar leaves. Do not duplicate flattened fields in the child.

5) Naming
- Entity names: TitleCase, singular (e.g., Users → User, user_roles → UserRole). Avoid generic collisions; prefer concrete names visible in the inputs.
- Never append raw file-format suffixes such as Json, Xml, Yaml, Csv, Pdf, Wsdl, or Xsd just because they appear in a filename.
- Attribute names: preserve source keys if clear; otherwise snake_case from the path (e.g., profile.firstName → profile_firstName → profile_first_name if needed).

6) Keys
- For each non-Assignment entity, ensure there is exactly one key attribute with "IsKey": true.
  a) Prefer an existing obvious key in samples/specs: "id", "{entity}_ID", "{entity}Id", GUID-like fields, or fields marked as identifiers (e.g., SCIM primary key, XSD key).
  b) If no obvious key exists, add "{Entity}_ID" with type:String and MultiValue:false and "IsKey": true.
- In Assignment entities, include the key attributes from both participating entities and set "IsKey": true on each of them; no extra synthetic key.

7) Source-aware hints (when present)
- SCIM: Use ResourceType + Schema names for entities; expand attributes and subAttributes (flatten subAttributes to parent as snake_case). Follow §6 for keys (e.g., "id" is key when present).
- WSDL/XSD: Use complexTypes/elements/parts to derive entities and attributes. Respect minOccurs/maxOccurs to infer MultiValue for repeated elements.
- CSV: Use header row for attributes.
- JSON: Derive from object keys; apply §4 for arrays/nesting.

8) Determinism & safety
- Be conservative: if unsure about type, choose String.
- Do not invent entities or attributes not present or reasonably implied by the inputs.
- No duplicates. If both "IsKey" and "isKey" appear in sources, keep only "IsKey" in the output.

Remember: return exactly one JSON schema object as specified—complete, sorted, and including all discovered attributes.`;

function bad(msg: string, status = 400) {
  return NextResponse.json({ ok: false, error: msg }, { status });
}

// ──────────────────────────────────────────────────────────────────────────────
// JSON attribute extractor — mirrors the n8n "Code in JavaScript" node logic.
// Produces a flat list of attribute names from the JSON shape.
// ──────────────────────────────────────────────────────────────────────────────
function isScalar(v: unknown): boolean {
  return v === null || ["string", "number", "boolean"].includes(typeof v);
}

function extractAttrsFromJson(data: unknown, depth = 0, maxDepth = 3): string[] {
  if (!data || typeof data !== "object") return [];

  // Unwrap root arrays: use the first object element as the shape
  if (Array.isArray(data)) {
    const first = data.find((x) => x && typeof x === "object" && !Array.isArray(x));
    return first ? extractAttrsFromJson(first, depth, maxDepth) : [];
  }

  const entries = Object.entries(data as Record<string, unknown>);

  // Unwrap single-key wrapper like { output: [...] }
  if (entries.length === 1 && typeof entries[0][1] === "object") {
    const inner = entries[0][1];
    if (Array.isArray(inner)) {
      const first = (inner as unknown[]).find(
        (x) => x && typeof x === "object" && !Array.isArray(x)
      );
      return first ? extractAttrsFromJson(first, depth, maxDepth) : [];
    }
    return extractAttrsFromJson(inner, depth, maxDepth);
  }

  const attrs: string[] = [];
  for (const [k, v] of entries) {
    if (isScalar(v) || Array.isArray(v)) {
      // scalars and arrays → single attribute on parent (MultiValue for arrays)
      attrs.push(k);
    } else if (v && typeof v === "object" && depth < maxDepth) {
      // flatten nested 1:1 object scalar leaves
      for (const [nk, nv] of Object.entries(v as Record<string, unknown>)) {
        attrs.push(isScalar(nv) ? `${k}_${nk}` : k);
      }
    } else {
      attrs.push(k);
    }
  }
  return attrs;
}

// ──────────────────────────────────────────────────────────────────────────────
// Background processing: parse file → call OpenAI → putResult
// ──────────────────────────────────────────────────────────────────────────────
async function processFile(
  file: File,
  requestId: string,
  fileType: string,
  fileName: string
): Promise<void> {
  try {
    const openai = new OpenAI({ apiKey: OPENAI_API_KEY, ...(OPENAI_BASE_URL ? { baseURL: OPENAI_BASE_URL } : {}) });
    let userMessage = "";
    const entityHint = fileNameToEntityHint(fileName);

    if (fileType === "application/json") {
      // Mirror: Json node → Code in JavaScript → Messages For Json → AI Agent
      const text = await file.text();
      let data: unknown;
      try {
        data = JSON.parse(text);
      } catch {
        data = text;
      }

      const attrs = extractAttrsFromJson(data);
      const requiredEntities = [{ name: entityHint, attributes: attrs.sort() }];
      const content = JSON.stringify({ requiredEntities }, null, 2);

      userMessage = [
        `File: ${fileName}`,
        `Type: ${fileType}`,
        `Entity name hint: ${entityHint}`,
        `Infer entities and attributes from this JSON sample using the system rules.`,
        `Content:`,
        content,
      ].join("\n");
    } else if (fileType === "application/pdf") {
      // Mirror: Extract from PDF → Messages for pdf → AI Agent
      const bytes = await file.arrayBuffer();
      const text = await extractPdfText(bytes);
      userMessage =
        `File: ${fileName}\n` +
        `Entity name hint: ${entityHint}\n` +
        `Infer entities and attributes from this file using the system rules.\n` +
        `Content:\n${text}`;
    } else if (fileType === "application/xml" || fileType === "text/xml") {
      // Mirror: Extract from XML → Messages for XML → AI Agent
      const text = await file.text();
      userMessage =
        `File: ${fileName}\n` +
        `Entity name hint: ${entityHint}\n` +
        `Infer entities and attributes from this file using the system rules.\n` +
        `Content:\n${text}`;
    } else {
      // Fallback: treat as plain text
      const text = await file.text();
      userMessage =
        `File: ${fileName}\n` +
        `Entity name hint: ${entityHint}\n` +
        `Infer entities and attributes from this file using the system rules.\n` +
        `Content:\n${text}`;
    }

    const completion = await openai.chat.completions.create({
      model: OPENAI_MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userMessage },
      ],
    });

    const raw = completion.choices[0]?.message?.content ?? "";

    // Strip accidental markdown fences before parsing
    const cleaned = raw
      .trim()
      .replace(/^```json\s*/i, "")
      .replace(/^```/, "")
      .replace(/```$/, "")
      .trim();

    let result: unknown;
    try {
      result = JSON.parse(cleaned);
    } catch {
      result = cleaned;
    }

    putResult(requestId, { ok: true, result });
  } catch (e: any) {
    putResult(requestId, { ok: false, error: e?.message ?? String(e) });
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Route handler
// ──────────────────────────────────────────────────────────────────────────────
export async function POST(req: NextRequest) {
  if (!OPENAI_API_KEY) return bad("server missing OPENAI_API_KEY", 500);

  let inForm: FormData;
  try {
    inForm = await req.formData();
  } catch {
    return bad("request must be multipart/form-data with a 'file' field");
  }

  const file = inForm.get("file");
  if (!(file instanceof File)) {
    return bad("no file provided (expected form field 'file')");
  }

  const rawId = inForm.get("request_id");
  if (!rawId || typeof rawId !== "string" || !rawId.trim()) {
    return bad("missing request_id");
  }
  const requestId = rawId.trim();

  const fileName = file.name || "upload.bin";
  const fileType =
    (inForm.get("fileType") as string | null) ||
    file.type ||
    "application/octet-stream";

  // Mirror n8n's SendBackPendingStatus: respond immediately, process in background.
  // setImmediate defers execution to after the response is fully flushed,
  // preventing Next.js from tracking this promise and blocking the handler.
  setImmediate(() => { void processFile(file, requestId, fileType, fileName); });

  return NextResponse.json({ ok: true, id: requestId, status: "pending" });
}
