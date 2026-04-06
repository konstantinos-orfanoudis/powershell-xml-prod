// app/api/ai/resultFiles/route.new.ts
// Native replacement for the n8n polling webhook (schema_json_result).
// Reads results from the local resultbus instead of polling n8n's datatable.
// The submitFile/route.new.ts populates the resultbus after AI processing.

import { NextRequest, NextResponse } from "next/server";
import { waitForResult } from "../../../../lib/resultbus";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function bad(msg: string, status = 400) {
  return NextResponse.json({ ok: false, error: msg }, { status });
}

export async function GET(req: NextRequest) {
  const id = new URL(req.url).searchParams.get("id");
  if (!id) return bad("missing ?id=<request_id>");

  try {
    // Wait up to 90 s — mirrors n8n's 6 × 10 s polling loop
    const payload = await waitForResult(id, 90_000);

    if (!payload.ok) {
      console.error("[resultFiles] processing failed:", payload.error);
      return NextResponse.json(
        { ok: false, error: payload.error },
        { status: 500 }
      );
    }

    return NextResponse.json({ ok: true, result: payload.result }, { status: 200 });
  } catch (e: any) {
    if (e?.message === "timeout") {
      // Mirror n8n's Respond 202: still processing
      return NextResponse.json({ ok: false, notReady: true }, { status: 200 });
    }
    return bad(e?.message || "result fetch failed", 502);
  }
}
