import { NextRequest, NextResponse } from "next/server";

import { loadImportedNotes } from "@/lib/sscp/notes";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

export async function POST(req: NextRequest) {
  let force = false;
  try {
    const body = await req.json().catch(() => null);
    force = Boolean(body?.force);
  } catch {
    force = false;
  }

  try {
    const chunks = await loadImportedNotes(force);
    const grouped = Object.fromEntries(
      chunks.reduce((acc, chunk) => {
        const list = acc.get(chunk.domainId) ?? [];
        list.push(chunk);
        acc.set(chunk.domainId, list);
        return acc;
      }, new Map<string, typeof chunks>())
        .entries(),
    );

    return NextResponse.json({
      ok: true,
      importedAt: new Date().toISOString(),
      totalChunks: chunks.length,
      chunks,
      grouped,
      sourcePolicy: {
        user_notes:
          "Imported PDF chunks are a supplemental reinforcement layer for this tutor alongside the official framework and trusted study references.",
      },
    });
  } catch (error: any) {
    return bad(error?.message ?? "Failed to import the local PDF study corpus.", 500);
  }
}
