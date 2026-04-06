// app/api/ai/submit/route.ts
// Thin wrapper — same native logic as receive/route.ts.
// Accepts plain text + x-filename header (existing UI contract) or JSON.

import { NextRequest, NextResponse } from 'next/server';
import { generateId, processSubmission } from '../../../../lib/ai-processor';

export const runtime = "nodejs";

function bad(msg: string, status = 400) {
  return NextResponse.json({ ok: false, error: msg }, { status });
}

export async function POST(req: NextRequest) {
  let message  = "";
  let fileText = "";
  let filename = "powershell-prototypes.ps1";

  const ct = req.headers.get("content-type") ?? "";
  if (ct.includes("application/json")) {
    let body: any;
    try { body = await req.json(); } catch { return bad("invalid JSON body"); }
    message  = String(body.message  ?? "");
    fileText = String(body.fileText ?? "");
    filename = String(body.filename ?? filename);
  } else {
    // Existing UI contract: plain PS text in body + x-filename header
    fileText = await req.text();
    filename = req.headers.get("x-filename") ?? filename;
  }

  const id = generateId();
  setImmediate(() => { void processSubmission(id, message, fileText, filename); });

  return NextResponse.json({ ok: true, id, status: "pending" });
}
