import { NextRequest, NextResponse } from "next/server";

import { addExtensionCapture } from "@/lib/sscp/captures";

export const runtime = "nodejs";

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

export async function POST(req: NextRequest) {
  let body:
    | {
        title?: string;
        url?: string;
        selectionText?: string;
        pageText?: string;
      }
    | null = null;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON payload.");
  }

  if (!body?.title || !body?.url) {
    return bad("Both title and url are required.");
  }

  try {
    const capture = await addExtensionCapture({
      title: body.title,
      url: body.url,
      selectionText: body.selectionText,
      pageText: body.pageText,
    });
    return NextResponse.json({ ok: true, capture });
  } catch (error: any) {
    return bad(error?.message ?? "Failed to store extension capture.", 500);
  }
}
