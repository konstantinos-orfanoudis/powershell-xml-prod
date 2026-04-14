import { NextRequest, NextResponse } from "next/server";

import type { ValidationReportExportRequest } from "@/app/XML-Validator/types";
import { buildValidationReportPdf } from "@/lib/xml-validator/pdf";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function bad(message: string, status = 400) {
  return NextResponse.json({ ok: false, error: message }, { status });
}

function buildFileName(generatedAt?: string) {
  const stamp = (generatedAt ? new Date(generatedAt) : new Date())
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d+Z$/, "Z");

  return `xml-validation-report-${stamp}.pdf`;
}

export async function POST(req: NextRequest) {
  let body: ValidationReportExportRequest | null = null;

  try {
    body = (await req.json()) as ValidationReportExportRequest;
  } catch {
    return bad("Invalid JSON payload.");
  }

  if (!body?.report) {
    return bad("Missing validation report.");
  }

  try {
    const pdf = buildValidationReportPdf(body);
    const fileName = buildFileName(body.generatedAt);

    return new NextResponse(pdf, {
      status: 200,
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="${fileName}"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (error: any) {
    return bad(error?.message ?? "Failed to generate PDF report.", 500);
  }
}
