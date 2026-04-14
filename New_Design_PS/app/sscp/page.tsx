import { Suspense } from "react";
import type { Metadata } from "next";

import SscpQuestionCoach from "@/app/sscp/SscpQuestionCoach";

export const metadata: Metadata = {
  title: "SSCP Mastery Coach",
  description:
    "Question-first SSCP study coach with CISSP and CTO answer lenses, trusted study paths, and PDF reinforcement.",
};

export default function SscpPage() {
  return (
    <Suspense
      fallback={
        <main className="min-h-screen bg-[linear-gradient(180deg,#f8f1e7_0%,#f4eadb_52%,#efe1cf_100%)] px-6 py-10 text-stone-900">
          <div className="mx-auto max-w-6xl rounded-[32px] border border-stone-900/10 bg-white/80 p-8 shadow-[0_12px_40px_rgba(63,46,32,0.08)]">
            <div className="text-xs uppercase tracking-[0.24em] text-stone-500">SSCP Coach</div>
            <h1 className="mt-4 text-3xl font-semibold tracking-tight text-stone-950">
              Loading the question lab
            </h1>
            <p className="mt-4 max-w-2xl text-sm leading-7 text-stone-600">
              Preparing challenging questions, answer lenses, trusted study paths, and PDF reinforcement for your SSCP/CISSP journey.
            </p>
          </div>
        </main>
      }
    >
      <SscpQuestionCoach />
    </Suspense>
  );
}
