// app/api/ai/result/route.ts
// Native replacement for the n8n "Powershell intragen" poll branch.
// Mirrors: Webhook → Read id → init → If → Get row(s) → Switch → Respond 200/202
// The receive/route.ts populates the resultbus after AI processing completes.

import { NextRequest, NextResponse } from "next/server";
import { waitForResult } from "../../../../lib/resultbus";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function bad(msg: string, status = 400) {
  return NextResponse.json({ error: msg }, { status });
}

export async function GET(req: NextRequest) {
  const id = req.nextUrl.searchParams.get("id");
  if (!id) return bad("missing id", 400);

  try {
    // Wait up to 5 min — the assistant + parallel tests/description pipeline can take 60-180 s
    const payload = await waitForResult(id, 300_000);

    if (!payload.ok) {
      console.error("[result] processing failed:", payload.error);
      return NextResponse.json({ error: payload.error }, { status: 500 });
    }

    // Mirror n8n "Prepare response" shape + "Respond 200" combined text
    const result      = String(payload.result      ?? "");
    const tests       = String(payload.tests       ?? "");
    const description = String(payload.description ?? "");
    const filename    = String(payload.filename     ?? "powershell-prototypes.ps1");
    const testsFilename = String(payload.testsFilename ?? filename.replace(/\.ps1$/i, ".tests.ps1"));

    // Combined plain-text body (mirrors n8n Respond 200 content)
    const combined =
      result +
      "\n\n<#\n--- Tests ---\n" + tests + "\n#>" +
      "\n\n<# --- Description ---\n" + description + "\n#>";

    // Return JSON — same shape the existing client expects from the old proxy
    return NextResponse.json({
      ok: true,
      status: "done",
      result: combined,   // backward-compat: full text in one field
      filename,
      testsFilename,
      tests,
      description,
    });
  } catch (e: any) {
    if (e?.message === "timeout") {
      // Mirror n8n Respond 202 pending
      return NextResponse.json({ ok: true, status: "pending" }, { status: 202 });
    }
    return bad(e?.message || "result fetch failed", 502);
  }
}
