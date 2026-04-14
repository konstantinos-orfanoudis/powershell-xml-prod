"use client";

import { useEffect, useMemo, useState } from "react";

import SscpReaderControls from "@/app/components/SscpReaderControls";
import { SOURCE_POLICY, SSCP_DOMAINS } from "@/lib/sscp/catalog";
import {
  DomainStudyMode,
  DrillResponse,
  QuestionAnswerLens,
  QuestionBlueprint,
  SourceTrustLevel,
  SscpDomainId,
  ThinkingLevel,
} from "@/lib/sscp/types";

function clsx(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(" ");
}

async function fetchJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  const json = await response.json();
  if (!response.ok) {
    throw new Error(json.error || "Request failed.");
  }
  return json as T;
}

function formatChronometer(totalSeconds: number) {
  const safe = Math.max(0, totalSeconds);
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  return [minutes, seconds].map((part) => String(part).padStart(2, "0")).join(":");
}

function SourceBadge({
  trustLevel,
}: {
  trustLevel: SourceTrustLevel;
}) {
  const label =
    trustLevel === "official"
      ? "Official"
      : trustLevel === "trusted_live"
        ? "Trusted"
        : "PDF notes";
  const tones =
    trustLevel === "official"
      ? "border-emerald-700/20 bg-emerald-50 text-emerald-900"
      : trustLevel === "trusted_live"
        ? "border-sky-700/20 bg-sky-50 text-sky-900"
        : "border-amber-700/20 bg-amber-50 text-amber-900";
  return (
    <span className={clsx("rounded-full border px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.14em]", tones)}>
      {label}
    </span>
  );
}

function LensCard({
  lens,
  isPriority,
}: {
  lens: QuestionAnswerLens;
  isPriority: boolean;
}) {
  return (
    <div
      className={clsx(
        "rounded-[22px] border p-5",
        isPriority ? "border-stone-900 bg-stone-900 text-stone-50" : "border-stone-900/10 bg-white/85 text-stone-900",
      )}
    >
      <div className={clsx("text-[11px] uppercase tracking-[0.2em]", isPriority ? "text-amber-300" : "text-stone-500")}>
        {lens.level}
      </div>
      <h4 className="mt-2 text-lg font-semibold">{lens.title}</h4>
      <p className={clsx("mt-3 text-sm leading-7", isPriority ? "text-stone-100" : "text-stone-700")}>
        {lens.answer}
      </p>
      <div className={clsx("mt-4 rounded-[18px] px-4 py-3 text-sm", isPriority ? "bg-white/8 text-stone-100" : "bg-stone-50 text-stone-700")}>
        <div className={clsx("font-semibold", isPriority ? "text-stone-50" : "text-stone-900")}>Why this lens thinks that way</div>
        <p className="mt-2 leading-7">{lens.explanation}</p>
      </div>
      <div className={clsx("mt-4 text-xs uppercase tracking-[0.18em]", isPriority ? "text-stone-300" : "text-stone-500")}>
        Focus
      </div>
      <p className={clsx("mt-2 text-sm leading-7", isPriority ? "text-stone-100" : "text-stone-700")}>{lens.focus}</p>
    </div>
  );
}

function QuestionCard({
  question,
  selectedLevel,
}: {
  question: QuestionBlueprint;
  selectedLevel: ThinkingLevel;
}) {
  const narrationText = [
    question.title,
    question.prompt,
    question.scenarioContext,
    ...question.answerLenses.map((lens) => `${lens.title}. ${lens.answer}. ${lens.explanation}`),
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <article className="rounded-[28px] border border-stone-900/10 bg-white/90 p-6 shadow-[0_12px_40px_rgba(63,46,32,0.08)]">
      <div className="flex flex-wrap items-center gap-2">
        <span className="rounded-full border border-stone-900/10 bg-stone-50 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-600">
          {question.difficultyLabel}
        </span>
        {question.domainIds.map((domainId) => {
          const domain = SSCP_DOMAINS.find((entry) => entry.id === domainId);
          return (
            <span
              key={`${question.id}-${domainId}`}
              className="rounded-full border border-stone-900/10 bg-stone-50 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-600"
            >
              {domain?.title ?? domainId}
            </span>
          );
        })}
        {question.sourceTypes.map((sourceType) => (
          <SourceBadge key={`${question.id}-${sourceType}`} trustLevel={sourceType} />
        ))}
      </div>
      <h3 className="mt-4 text-2xl font-semibold tracking-tight text-stone-950">{question.title}</h3>
      <p className="mt-4 text-sm leading-8 text-stone-700">{question.prompt}</p>
      {question.scenarioContext ? (
        <div className="mt-4 rounded-[18px] bg-stone-50 px-4 py-3 text-sm leading-7 text-stone-700">
          <span className="font-semibold text-stone-900">Scenario context:</span> {question.scenarioContext}
        </div>
      ) : null}

      {question.options?.length ? (
        <div className="mt-5 space-y-2">
          {question.options.map((option) => (
            <div key={option.id} className="rounded-[16px] border border-stone-900/10 bg-white px-4 py-3 text-sm text-stone-700">
              <span className="font-semibold text-stone-900">{option.label}.</span> {option.text}
            </div>
          ))}
        </div>
      ) : null}

      <div className="mt-5 flex flex-wrap items-center gap-3">
        <span className="rounded-full border border-emerald-700/20 bg-emerald-50 px-4 py-2 text-sm font-semibold text-emerald-900">
          Answers and explanations are displayed below
        </span>
        <SscpReaderControls text={narrationText} label="question and answers" />
      </div>

      <div className="mt-6 space-y-4">
        <div className="rounded-[20px] border border-emerald-700/20 bg-emerald-50/80 px-4 py-4 text-sm leading-7 text-emerald-950">
          <span className="font-semibold">Best-answer core:</span> {question.idealAnswer}
        </div>
        <div className="grid gap-4 xl:grid-cols-3">
          {question.answerLenses.map((lens) => (
            <LensCard
              key={`${question.id}-${lens.level}`}
              lens={lens}
              isPriority={lens.level === selectedLevel}
            />
          ))}
        </div>
        {question.optionRationales?.length ? (
          <div className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-5">
            <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Why the options behave differently</div>
            <ul className="mt-3 space-y-2 text-sm leading-7 text-stone-700">
              {question.optionRationales.map((item) => {
                const option = question.options?.find((entry) => entry.id === item.optionId);
                return (
                  <li key={`${question.id}-${item.optionId}`}>
                    <span className="font-semibold text-stone-900">{option?.label ?? item.optionId.toUpperCase()}.</span>{" "}
                    {item.rationale}
                  </li>
                );
              })}
            </ul>
          </div>
        ) : null}
        <div className="grid gap-4 xl:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)]">
          <div className="rounded-[22px] border border-stone-900/10 bg-white/85 p-5">
            <div className="text-xs uppercase tracking-[0.22em] text-stone-500">How to study this answer set</div>
            <ul className="mt-3 space-y-2 text-sm leading-7 text-stone-700">
              {question.answerGuidance.map((item) => (
                <li key={item}>• {item}</li>
              ))}
            </ul>
            <div className="mt-4 rounded-[16px] bg-stone-50 px-4 py-3 text-sm leading-7 text-stone-700">
              <span className="font-semibold text-stone-900">Strategic takeaway:</span> {question.strategicTakeaway}
            </div>
          </div>
          <div className="rounded-[22px] border border-stone-900/10 bg-white/85 p-5">
            <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Source trail</div>
            <div className="mt-3 flex flex-wrap gap-2">
              {question.citations.map((citation) => (
                <span
                  key={citation.id}
                  className="rounded-full border border-stone-900/10 bg-stone-50 px-3 py-1 text-xs text-stone-600"
                >
                  {citation.sourceName}
                </span>
              ))}
            </div>
            <div className="mt-4 text-xs uppercase tracking-[0.22em] text-stone-500">Revisit these key phrases</div>
            <div className="mt-2 flex flex-wrap gap-2">
              {question.answerKeyPhrases.map((phrase) => (
                <span
                  key={phrase}
                  className="rounded-full border border-amber-700/20 bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-900"
                >
                  {phrase}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>
    </article>
  );
}

function Chronometer({ startedAt }: { startedAt: string | null }) {
  const [elapsedSeconds, setElapsedSeconds] = useState(0);

  useEffect(() => {
    if (!startedAt) {
      setElapsedSeconds(0);
      return;
    }

    const update = () => {
      const started = new Date(startedAt).getTime();
      setElapsedSeconds(Math.max(0, Math.floor((Date.now() - started) / 1000)));
    };

    update();
    const interval = window.setInterval(update, 1000);
    return () => window.clearInterval(interval);
  }, [startedAt]);

  return (
    <div className="rounded-[22px] border border-stone-900/10 bg-white/85 px-5 py-4">
      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Thinking timer</div>
      <div className="mt-2 text-3xl font-semibold tracking-tight text-stone-950">{formatChronometer(elapsedSeconds)}</div>
      <p className="mt-2 text-sm leading-7 text-stone-600">
        Start thinking before you reveal the answers. The answer lenses are there to sharpen your reasoning, not replace it.
      </p>
    </div>
  );
}

export default function SscpQuestionCoach() {
  const [focusDomain, setFocusDomain] = useState<SscpDomainId>("security-concepts-practices");
  const [domainMode, setDomainMode] = useState<DomainStudyMode>("combined");
  const [thinkingLevel, setThinkingLevel] = useState<ThinkingLevel>("cissp");
  const [questionMode, setQuestionMode] = useState<"mixed" | "multiple_choice" | "short_answer" | "scenario">("mixed");
  const [questionCount, setQuestionCount] = useState(4);
  const [topicHint, setTopicHint] = useState("zero trust, incident handling, access decisions");
  const [response, setResponse] = useState<DrillResponse | null>(null);
  const [status, setStatus] = useState("Ready to generate hard questions.");
  const [startedAt, setStartedAt] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);

  const selectedDomainMeta = SSCP_DOMAINS.find((domain) => domain.id === focusDomain) ?? SSCP_DOMAINS[0];

  const headline = useMemo(() => {
    if (domainMode === "single") {
      return `Generate ${thinkingLevel.toUpperCase()}-style exam questions for ${selectedDomainMeta.title}`;
    }
    return `Generate cross-domain ${thinkingLevel.toUpperCase()}-style exam questions from ${selectedDomainMeta.title}`;
  }, [domainMode, thinkingLevel, selectedDomainMeta.title]);

  async function generateQuestions() {
    setIsLoading(true);
    setStatus("Generating certification-style questions with SSCP, CISSP, and CTO answer lenses...");
    setResponse(null);
    setStartedAt(new Date().toISOString());
    try {
      const difficulty =
        thinkingLevel === "sscp"
          ? "foundation"
          : thinkingLevel === "cissp"
            ? "pressure"
            : "bridge";

      const data = await fetchJson<DrillResponse>("/api/sscp/drill", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          domainIds: [focusDomain],
          mode: questionMode,
          count: questionCount,
          difficulty,
          thinkingLevel,
          domainMode,
          topicHint,
          generationNonce: Date.now(),
        }),
      });
      setResponse(data);
      setStatus("Question set with answers ready.");
    } catch (error: any) {
      setStatus(error?.message ?? "Failed to generate questions.");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <main
      data-coach-ready="true"
      className="min-h-screen bg-[linear-gradient(180deg,#f8f1e7_0%,#f4eadb_52%,#efe1cf_100%)] px-5 py-8 text-stone-900 md:px-8"
    >
      <div className="mx-auto max-w-7xl space-y-6">
        <section className="rounded-[32px] border border-stone-900/10 bg-stone-900 px-6 py-8 text-stone-50 shadow-[0_16px_50px_rgba(28,21,16,0.18)] md:px-8">
          <div className="text-xs uppercase tracking-[0.28em] text-stone-300">Question lab</div>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight">SSCP / CISSP / CTO Question Tutor</h1>
          <p className="mt-4 max-w-4xl text-sm leading-8 text-stone-200">
            Keep the flow simple: generate hard exam-style questions and study the answers directly underneath them.
            Every question includes three answer lenses so you can compare how an SSCP, a CISSP, and a CTO may respond.
          </p>
          <div className="mt-5 flex flex-wrap gap-2">
            {Object.entries(SOURCE_POLICY).map(([key, description]) => (
              <div key={key} className="rounded-[18px] border border-white/12 bg-white/6 px-4 py-3">
                <SourceBadge trustLevel={key as SourceTrustLevel} />
                <p className="mt-2 max-w-xs text-xs leading-6 text-stone-300">{description}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="grid gap-6 xl:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)]">
          <div className="rounded-[28px] border border-stone-900/10 bg-white/90 p-6 shadow-[0_12px_40px_rgba(63,46,32,0.08)]">
            <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Question generator</div>
            <h2 className="mt-3 text-2xl font-semibold tracking-tight text-stone-950">{headline}</h2>
            <p className="mt-3 text-sm leading-7 text-stone-600">
              Choose whether the questions stay inside one domain or blend knowledge across related domains. The selected level changes how aggressive and strategic the exam questions feel, but every question still shows all three answer lenses.
            </p>
            <div className="mt-6 grid gap-4 md:grid-cols-2">
              <label className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-4">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Focus domain</div>
                <select
                  value={focusDomain}
                  onChange={(event) => setFocusDomain(event.target.value as SscpDomainId)}
                  className="mt-3 w-full rounded-[16px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none"
                >
                  {SSCP_DOMAINS.map((domain) => (
                    <option key={domain.id} value={domain.id}>
                      {domain.title}
                    </option>
                  ))}
                </select>
              </label>

              <label className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-4">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Question style</div>
                <select
                  value={questionMode}
                  onChange={(event) => setQuestionMode(event.target.value as "mixed" | "multiple_choice" | "short_answer" | "scenario")}
                  className="mt-3 w-full rounded-[16px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none"
                >
                  <option value="mixed">Exam mix</option>
                  <option value="multiple_choice">Single best answer</option>
                  <option value="scenario">Scenario exam</option>
                  <option value="short_answer">Short answer</option>
                </select>
              </label>

              <div className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-4">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Domain mode</div>
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  {([
                    { value: "combined", label: "Combined domains" },
                    { value: "single", label: "Single domain" },
                  ] as const).map((option) => (
                    <button
                      key={option.value}
                      type="button"
                      onClick={() => setDomainMode(option.value)}
                      className={clsx(
                        "rounded-[16px] border px-4 py-3 text-sm font-semibold transition",
                        domainMode === option.value
                          ? "border-stone-900 bg-stone-900 text-stone-50"
                          : "border-stone-900/10 bg-white text-stone-700 hover:bg-stone-100",
                      )}
                    >
                      {option.label}
                    </button>
                  ))}
                </div>
              </div>

              <div className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-4">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Thinking level</div>
                <div className="mt-3 grid gap-2 sm:grid-cols-3">
                  {([
                    { value: "sscp", label: "SSCP" },
                    { value: "cissp", label: "CISSP" },
                    { value: "cto", label: "CTO" },
                  ] as const).map((option) => (
                    <button
                      key={option.value}
                      type="button"
                      onClick={() => setThinkingLevel(option.value)}
                      className={clsx(
                        "rounded-[16px] border px-4 py-3 text-sm font-semibold transition",
                        thinkingLevel === option.value
                          ? "border-stone-900 bg-stone-900 text-stone-50"
                          : "border-stone-900/10 bg-white text-stone-700 hover:bg-stone-100",
                      )}
                    >
                      {option.label}
                    </button>
                  ))}
                </div>
              </div>

              <label className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-4">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Question count</div>
                <select
                  value={questionCount}
                  onChange={(event) => setQuestionCount(Number(event.target.value))}
                  className="mt-3 w-full rounded-[16px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none"
                >
                  <option value={3}>3</option>
                  <option value={4}>4</option>
                  <option value={6}>6</option>
                </select>
              </label>

              <label className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-4">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Topic hint</div>
                <input
                  type="text"
                  value={topicHint}
                  onChange={(event) => setTopicHint(event.target.value)}
                  className="mt-3 w-full rounded-[16px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none"
                  placeholder="Zero trust, incident escalation, cloud risk..."
                />
              </label>
            </div>

            <div className="mt-6 flex flex-wrap items-center gap-3">
              <button
                type="button"
                onClick={() => void generateQuestions()}
                disabled={isLoading}
                className={clsx(
                  "rounded-full border border-stone-900 bg-stone-900 px-5 py-3 text-sm font-semibold text-stone-50 transition hover:bg-stone-800",
                  isLoading && "cursor-not-allowed opacity-60",
                )}
              >
                {isLoading ? "Generating questions..." : "Generate questions"}
              </button>
              <span className="text-sm text-stone-600">{status}</span>
            </div>
          </div>

          <div className="space-y-6">
            <Chronometer startedAt={startedAt} />
            <div className="rounded-[28px] border border-stone-900/10 bg-white/90 p-6 shadow-[0_12px_40px_rgba(63,46,32,0.08)]">
              <div className="text-xs uppercase tracking-[0.22em] text-stone-500">How to use this</div>
              <ol className="mt-4 space-y-3 text-sm leading-7 text-stone-700">
                <li>1. Generate a full question set.</li>
                <li>2. Read each exam question and the answer options first, before looking at the explanation.</li>
                <li>3. Then study the SSCP, CISSP, and CTO answers shown underneath it.</li>
                <li>4. Compare how the three levels differ in depth, tradeoffs, and leadership framing.</li>
                <li>5. If the question hurts, revisit theory or sources and generate another round.</li>
              </ol>
            </div>
            {response ? (
              <div className="rounded-[28px] border border-stone-900/10 bg-white/90 p-6 shadow-[0_12px_40px_rgba(63,46,32,0.08)]">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Study loop</div>
                <div className="mt-3 text-sm leading-7 text-stone-700">
                  <span className="font-semibold text-stone-900">Next move:</span> {response.recommendedNextTask}
                </div>
                <div className="mt-4 flex flex-wrap gap-2">
                  {response.missedConcepts.map((item) => (
                    <span
                      key={item}
                      className="rounded-full border border-amber-700/20 bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-900"
                    >
                      {item}
                    </span>
                  ))}
                </div>
              </div>
            ) : null}
          </div>
        </section>

        <section className="space-y-6">
          {response ? (
            response.questions.map((question) => (
              <QuestionCard
                key={question.id}
                question={question}
                selectedLevel={response.selectedLevel}
              />
            ))
          ) : (
            <div className="rounded-[28px] border border-dashed border-stone-900/20 bg-white/70 p-8 text-sm leading-8 text-stone-600">
              Generate a question set to start. The tutor will give you challenging prompts, source-backed context, and three answer lenses every time.
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
