import { NextRequest, NextResponse } from "next/server";

import { buildTeachResponse } from "@/lib/sscp/engine";
import { loadCachedImportedNotes } from "@/lib/sscp/notes";
import { SscpDomainId } from "@/lib/sscp/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

export async function POST(req: NextRequest) {
  let body: { domainId?: SscpDomainId } | null = null;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON payload.");
  }

  if (!body?.domainId) {
    return bad("Missing domainId.");
  }

  try {
    const notes = await loadCachedImportedNotes();
    const lesson = buildTeachResponse(body.domainId, notes);
    return NextResponse.json({ ok: true, ...lesson });
  } catch (error: any) {
    return bad(error?.message ?? "Failed to build lesson.", 500);
  }
}
