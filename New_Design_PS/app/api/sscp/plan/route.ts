import { NextRequest, NextResponse } from "next/server";

import { buildStudyPlan, createEmptyMasterySnapshot, normalizeMastery } from "@/lib/sscp/engine";
import { PlanRequest } from "@/lib/sscp/types";

export const runtime = "nodejs";

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

export async function POST(req: NextRequest) {
  let body: Partial<PlanRequest> | null = null;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON payload.");
  }

  if (!body?.profile) {
    return bad("Missing profile.");
  }

  try {
    const plan = buildStudyPlan({
      profile: body.profile,
      mastery: normalizeMastery(body.mastery ?? createEmptyMasterySnapshot()),
    });
    return NextResponse.json({
      ok: true,
      plan,
      sourcePolicy: {
        official: "Official SSCP/CISSP domain framing stays primary for readiness and mastery.",
        trusted_live: "Trusted study guides and reference material deepen lessons and reading paths.",
        user_notes: "The local PDF study corpus is loaded as supplemental reinforcement for lessons, drills, and review.",
      },
    });
  } catch (error: any) {
    return bad(error?.message ?? "Failed to build plan.", 500);
  }
}
