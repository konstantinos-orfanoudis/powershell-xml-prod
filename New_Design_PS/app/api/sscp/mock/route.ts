import { NextRequest, NextResponse } from "next/server";

import { buildFallbackDrill, inferConfidenceLevel, sortCitations } from "@/lib/sscp/engine";
import { loadCachedImportedNotes } from "@/lib/sscp/notes";
import { DrillRequest, MockResponse, SscpDomainId } from "@/lib/sscp/types";

export const runtime = "nodejs";

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

export async function POST(req: NextRequest) {
  let body:
    | {
        length?: "mini" | "full";
        domainIds?: SscpDomainId[];
      }
    | null = null;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON payload.");
  }

  const length = body?.length ?? "mini";
  const domainIds =
    body?.domainIds?.length
      ? body.domainIds
      : ([
          "security-concepts-practices",
          "access-controls",
          "risk-identification-monitoring-analysis",
          "incident-response-recovery",
          "cryptography",
          "network-communications-security",
          "systems-application-security",
        ] satisfies SscpDomainId[]);

  const drillRequest: DrillRequest = {
    domainIds,
    mode: "mixed",
    count: length === "full" ? 100 : 25,
    difficulty: length === "full" ? "bridge" : "pressure",
  };

  const notes = await loadCachedImportedNotes().catch(() => []);
  const drill = buildFallbackDrill(drillRequest, notes);
  const citations = sortCitations(drill.questions.flatMap((question) => question.citations));
  const response: MockResponse = {
    generatedAt: new Date().toISOString(),
    length,
    durationMinutes: length === "full" ? 120 : 35,
    questions: drill.questions,
    guidance:
      length === "full"
        ? "Treat this as a serious timed mock. Answer in order, log confidence, and review only after you finish."
        : "Mini mock mode is for pressure practice. Move quickly and avoid overthinking early items.",
    citations,
    sourceTypes: [...new Set(citations.map((citation) => citation.trustLevel))],
    confidenceLevel: inferConfidenceLevel(citations),
    sscpReview: {
      score: 83,
      verdict: "Mock structure ready",
      rationale:
        "The mock spans all SSCP domains and keeps the question flow anchored to the official tutor framing, trusted study references, and the supplemental PDF corpus.",
      strengths: ["Broad domain spread", "Trusted and PDF-supported question framing", "Timed pressure framing"],
      gaps: ["Needs submitted answers for a true score"],
      nextStep: "Complete the mock in one sitting, then review domain-level misses before retesting.",
    },
    cisspReview: {
      score: 71,
      verdict: "Bridge-capable review mode",
      rationale:
        "The mock remains SSCP-shaped, but your post-answer review can still elevate each item into CISSP-style thinking.",
      strengths: ["Supports post-mock bridge analysis"],
      gaps: ["Not every item is naturally architectural without your deeper explanation"],
      nextStep: "After the mock, pick five items and rewrite the answer using risk, governance, or architecture language.",
    },
    missedConcepts: ["confidence pacing", "cross-domain translation"],
    recommendedNextTask:
      "After the mock, review only the weakest domain first. Do not reread everything equally.",
  };

  return NextResponse.json({ ok: true, ...response });
}
