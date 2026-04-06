// app/api/ai/receive/route.ts
// Native replacement for the n8n "Powershell intragen" submit branch.
// Flow: receive { message, fileText } → respond pending → background:
//   OpenAI Responses API (PS generation) → Tests Gen → Description → putResult
// Companion: result/route.ts reads the result via waitForResult.

import { NextRequest, NextResponse } from "next/server";
import { generateId, processSubmission } from "../../../../lib/ai-processor";

export const runtime = "nodejs";

function bad(msg: string, status = 400) {
  return NextResponse.json({ ok: false, error: msg }, { status });
}

export async function POST(req: NextRequest) {
  if (!process.env.OPENAI_API_KEY) return bad("server missing OPENAI_API_KEY", 500);

  let message = "";
  let fileText = "";
  let filename = "powershell-prototypes.ps1";

  const ct = req.headers.get("content-type") ?? "";
  if (ct.includes("application/json")) {
    // Primary format used by the PS tool: { message, fileText, filename? }
    let body: any;
    try {
      body = await req.json();
    } catch {
      return bad("invalid JSON body");
    }
    message = String(body.message ?? "");
    fileText = String(body.fileText ?? "");
    filename = String(body.filename ?? filename);
  } else {
    // Backward-compat: plain PS text in body + optional x-filename header
    fileText = await req.text();
    filename = req.headers.get("x-filename") ?? filename;
  }

  const id = generateId();
  setImmediate(() => {
    void processSubmission(id, message, fileText, filename);
  });

  return NextResponse.json({ ok: true, id, status: "pending" }, { status: 202 });
}
