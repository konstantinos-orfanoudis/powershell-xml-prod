import { NextResponse } from "next/server";

import { listExtensionCaptures, markCaptureProcessed } from "@/lib/sscp/captures";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const captures = await listExtensionCaptures();
  return NextResponse.json({ ok: true, captures });
}

export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  if (body?.id) {
    await markCaptureProcessed(body.id);
  }
  return NextResponse.json({ ok: true });
}
