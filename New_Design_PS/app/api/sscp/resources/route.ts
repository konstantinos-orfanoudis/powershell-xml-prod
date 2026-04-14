import { NextRequest, NextResponse } from "next/server";

import { buildFallbackResources } from "@/lib/sscp/engine";
import { loadCachedImportedNotes } from "@/lib/sscp/notes";
import { SscpDomainId } from "@/lib/sscp/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

export async function POST(req: NextRequest) {
  let body: { domainIds?: SscpDomainId[]; topicHint?: string } | null = null;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON payload.");
  }

  const domainIds =
    body?.domainIds?.length
      ? body.domainIds
      : (["security-concepts-practices"] satisfies SscpDomainId[]);

  try {
    const notes = await loadCachedImportedNotes();
    const curated = buildFallbackResources(domainIds, notes, body?.topicHint?.trim());

    return NextResponse.json({
      ok: true,
      summary: body?.topicHint?.trim()
        ? `Showing validated study paths for ${body.topicHint.trim()} using the official tutor framework, trusted guides, and related PDF excerpts from your SSCP/CISSP book corpus.`
        : "Showing validated study paths from the official tutor framework, trusted guides, and your supplemental SSCP/CISSP PDF corpus.",
      curated,
      live: [],
    });
  } catch (error: any) {
    return bad(error?.message ?? "Failed to load validated study resources.", 500);
  }
}
