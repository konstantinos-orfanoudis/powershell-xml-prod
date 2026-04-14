"use client";

import React, { startTransition, type ReactNode, useDeferredValue, useEffect, useMemo, useState, useTransition } from "react";
import { useSearchParams } from "next/navigation";

import { ActionHealthPanel, CaptureStudyAidCard, CheckpointLab, FlashcardDeck, ScenarioStudio, StrategicLensCard, WorkedExampleStudio } from "@/app/components/InteractiveStudy";
import SscpReaderControls from "@/app/components/SscpReaderControls";
import { StudyDiagramExplorer, StudyFlowDiagram, StudyMindmap } from "@/app/components/StudyVisuals";
import { SOURCE_POLICY, SSCP_DOMAINS } from "@/lib/sscp/catalog";
import { ACTION_HEALTH_MATRIX, buildCaptureStudyAid } from "@/lib/sscp/coach-utils";
import {
  createEmptyMasterySnapshot,
  normalizeMastery,
} from "@/lib/sscp/engine";
import {
  CaptureStudyAid,
  DualReview,
  DrillResponse,
  ExtensionCapture,
  ImportedNoteChunk,
  LearnerProfile,
  LearningResource,
  MasterySnapshot,
  MockResponse,
  QuestionAttempt,
  QuestionBlueprint,
  ReviewPanel,
  SourceTrustLevel,
  SscpDomainId,
  StudySprintPlan,
  TeachResponse,
} from "@/lib/sscp/types";

const STORAGE_KEY = "sscp-coach-state-v2";

type Workspace = "plan" | "learn" | "drill" | "resources" | "library";
type BusyActionKey =
  | "notes"
  | "plan"
  | "lesson"
  | "resources"
  | "drill"
  | "mock"
  | "captures"
  | `evaluate:${string}`;

interface PersistedCoachState {
  profile: LearnerProfile;
  mastery: MasterySnapshot;
  notes: ImportedNoteChunk[];
  savedResources: LearningResource[];
}

function makeDefaultProfile(): LearnerProfile {
  return {
    learnerName: "",
    weeklyHours: 8,
    currentRole: "Security practitioner",
    targetMode: "mastery",
    strengths: ["network-communications-security"],
    weakAreas: [
      "security-concepts-practices",
      "risk-identification-monitoring-analysis",
    ],
    currentConfidence: 52,
  };
}

async function fetchJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  const json = await response.json();
  if (!response.ok) {
    throw new Error(json.error || "Request failed.");
  }
  return json as T;
}

function clsx(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(" ");
}

function surfaceClass(tone: "cream" | "white" | "ink" = "white") {
  if (tone === "cream") {
    return "rounded-[28px] border border-amber-950/10 bg-[linear-gradient(180deg,rgba(250,245,237,0.95),rgba(247,241,231,0.9))] shadow-[0_12px_40px_rgba(63,46,32,0.08)]";
  }
  if (tone === "ink") {
    return "rounded-[28px] border border-stone-900/10 bg-stone-900 text-stone-50 shadow-[0_12px_40px_rgba(28,21,16,0.18)]";
  }
  return "rounded-[28px] border border-stone-900/8 bg-white/85 shadow-[0_12px_40px_rgba(63,46,32,0.08)]";
}

function MetricPill({
  label,
  value,
  accent = "text-stone-900",
}: {
  label: string;
  value: string;
  accent?: string;
}) {
  return (
    <div className="rounded-full border border-stone-900/10 bg-white/70 px-4 py-2">
      <div className="text-[11px] uppercase tracking-[0.22em] text-stone-500">{label}</div>
      <div className={clsx("text-lg font-semibold", accent)}>{value}</div>
    </div>
  );
}

function LoadingPanel({
  eyebrow,
  title,
  body,
}: {
  eyebrow: string;
  title: string;
  body: string;
}) {
  return (
    <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">{eyebrow}</div>
      <div className="mt-3 text-lg font-semibold text-stone-900">{title}</div>
      <p className="mt-2 text-sm leading-7 text-stone-600">{body}</p>
      <div className="mt-4 h-2 rounded-full bg-stone-100">
        <div className="h-full w-2/3 animate-pulse rounded-full bg-stone-300" />
      </div>
    </div>
  );
}

function formatChronometer(totalSeconds: number) {
  const safe = Math.max(0, totalSeconds);
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  const seconds = safe % 60;

  if (hours > 0) {
    return [hours, minutes, seconds].map((part) => String(part).padStart(2, "0")).join(":");
  }

  return [minutes, seconds].map((part) => String(part).padStart(2, "0")).join(":");
}

function ExpectedAnswerPanel({
  question,
}: {
  question: QuestionBlueprint;
}) {
  const correctOptions =
    question.options?.filter((option) => question.correctOptionIds?.includes(option.id)) ?? [];
  const narrationText = [
    correctOptions.length
      ? `Correct options: ${correctOptions.map((option) => `${option.label}. ${option.text}`).join(" ")}`
      : "",
    `Ideal answer. ${question.idealAnswer}`,
    question.answerGuidance.length
      ? `Answer guidance. ${question.answerGuidance.join(" ")}`
      : "",
    question.strategicTakeaway ? `Strategic takeaway. ${question.strategicTakeaway}` : "",
    question.answerKeyPhrases.length
      ? `Key phrases. ${question.answerKeyPhrases.join(", ")}`
      : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <div className="mt-5 space-y-4 rounded-[22px] border border-emerald-700/20 bg-emerald-50/70 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <span className="rounded-full border border-emerald-700/20 bg-white px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-emerald-900">
          Expected answer
        </span>
        <span className="text-xs text-emerald-900/80">
          Reveal is a study aid. Mastery only updates when you submit for evaluation.
        </span>
      </div>
      {correctOptions.length ? (
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-emerald-900/70">
            Correct option{correctOptions.length > 1 ? "s" : ""}
          </div>
          <ul className="mt-2 space-y-2 text-sm text-emerald-950">
            {correctOptions.map((option) => (
              <li key={option.id}>
                <span className="font-semibold">{option.label}.</span> {option.text}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      <div>
        <div className="text-xs uppercase tracking-[0.22em] text-emerald-900/70">Model answer</div>
        <p className="mt-2 text-sm leading-7 text-emerald-950">{question.idealAnswer}</p>
      </div>
      {question.optionRationales?.length ? (
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-emerald-900/70">Why the options behave differently</div>
          <ul className="mt-2 space-y-2 text-sm text-emerald-950">
            {question.optionRationales.map((item) => {
              const option = question.options?.find((entry) => entry.id === item.optionId);
              return (
                <li key={`${question.id}-${item.optionId}`}>
                  <span className="font-semibold">{option?.label ?? item.optionId.toUpperCase()}.</span> {item.rationale}
                </li>
              );
            })}
          </ul>
        </div>
      ) : null}
      <div className="grid gap-4 md:grid-cols-2">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-emerald-900/70">Guidance</div>
          <ul className="mt-2 space-y-2 text-sm text-emerald-950">
            {question.answerGuidance.map((item) => (
              <li key={item}>• {item}</li>
            ))}
          </ul>
        </div>
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-emerald-900/70">Key phrases</div>
          <div className="mt-2 flex flex-wrap gap-2">
            {question.answerKeyPhrases.map((phrase) => (
              <span
                key={phrase}
                className="rounded-full border border-emerald-700/20 bg-white px-3 py-1 text-xs font-semibold text-emerald-950"
              >
                {phrase}
              </span>
            ))}
          </div>
        </div>
      </div>
      <div className="rounded-[18px] bg-white px-4 py-3 text-sm text-emerald-950">
        <span className="font-semibold">Strategic takeaway:</span> {question.strategicTakeaway}
      </div>
      <SscpReaderControls text={narrationText} label="expected answer" />
    </div>
  );
}

function ChronometerCard({
  startedAt,
  durationMinutes,
  label,
  onRestart,
}: {
  startedAt: string | null;
  durationMinutes?: number;
  label: string;
  onRestart: () => void;
}) {
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

  const targetSeconds = durationMinutes ? durationMinutes * 60 : null;
  const remainingSeconds =
    targetSeconds === null ? null : Math.max(0, targetSeconds - elapsedSeconds);
  const isOvertime = targetSeconds !== null && elapsedSeconds > targetSeconds;

  return (
    <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">{label}</div>
          <div className="mt-2 text-3xl font-semibold tracking-tight text-stone-950">
            {formatChronometer(elapsedSeconds)}
          </div>
        </div>
        <button
          type="button"
          onClick={onRestart}
          className="rounded-full border border-stone-900/10 bg-white px-3 py-1.5 text-xs font-semibold text-stone-700 transition hover:bg-stone-100"
        >
          Restart timer
        </button>
      </div>
      <div className="mt-4 flex flex-wrap gap-3">
        <MetricPill label="Elapsed" value={formatChronometer(elapsedSeconds)} />
        {targetSeconds !== null ? (
          <>
            <MetricPill label="Target" value={`${durationMinutes} min`} />
            <MetricPill
              label={isOvertime ? "Overtime" : "Remaining"}
              value={formatChronometer(isOvertime ? elapsedSeconds - targetSeconds : remainingSeconds ?? 0)}
              accent={isOvertime ? "text-rose-700" : "text-emerald-700"}
            />
          </>
        ) : null}
      </div>
    </div>
  );
}

function SourceBadge({
  trustLevel,
  label,
}: {
  trustLevel: SourceTrustLevel;
  label: string;
}) {
  const tones: Record<SourceTrustLevel, string> = {
    official: "border-emerald-700/20 bg-emerald-50 text-emerald-900",
    trusted_live: "border-sky-700/20 bg-sky-50 text-sky-900",
    user_notes: "border-amber-700/20 bg-amber-50 text-amber-900",
  };

  return (
    <span className={clsx("rounded-full border px-2.5 py-1 text-[11px] font-semibold", tones[trustLevel])}>
      {label}
    </span>
  );
}

function WorkspaceButton({
  active,
  onClick,
  title,
  blurb,
}: {
  active: boolean;
  onClick: () => void;
  title: string;
  blurb: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={clsx(
        "w-full rounded-[22px] border px-4 py-4 text-left transition",
        active
          ? "border-stone-900 bg-stone-900 text-stone-50"
          : "border-stone-900/10 bg-white/70 text-stone-900 hover:border-stone-900/20 hover:bg-white",
      )}
    >
      <div className="text-sm font-semibold">{title}</div>
      <div className={clsx("mt-1 text-xs leading-5", active ? "text-stone-300" : "text-stone-500")}>
        {blurb}
      </div>
    </button>
  );
}

function SectionShell({
  title,
  subtitle,
  actions,
  children,
  tone = "white",
}: {
  title: string;
  subtitle: string;
  actions?: ReactNode;
  children: ReactNode;
  tone?: "cream" | "white" | "ink";
}) {
  return (
    <section className={clsx(surfaceClass(tone), "p-6 md:p-8")}>
      <div className="flex flex-col gap-4 border-b border-stone-900/10 pb-5 md:flex-row md:items-end md:justify-between">
        <div className="max-w-3xl">
          <div className={clsx("text-xs uppercase tracking-[0.28em]", tone === "ink" ? "text-stone-400" : "text-stone-500")}>
            SSCP Mastery Coach
          </div>
          <h2 className="mt-2 text-2xl font-semibold tracking-tight">{title}</h2>
          <p className={clsx("mt-2 max-w-2xl text-sm leading-6", tone === "ink" ? "text-stone-300" : "text-stone-600")}>
            {subtitle}
          </p>
        </div>
        {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
      </div>
      <div className="mt-6">{children}</div>
    </section>
  );
}

function ReviewPanelCard({
  title,
  panel,
}: {
  title: string;
  panel: ReviewPanel;
}) {
  return (
    <div className="rounded-[22px] border border-stone-900/10 bg-white/80 p-5">
      <div className="flex items-center justify-between gap-4">
        <h4 className="text-lg font-semibold text-stone-900">{title}</h4>
        <span className="rounded-full border border-stone-900/10 bg-stone-900 px-3 py-1 text-sm font-semibold text-stone-50">
          {panel.score}
        </span>
      </div>
      <div className="mt-2 text-sm font-medium text-stone-700">{panel.verdict}</div>
      <p className="mt-3 text-sm leading-6 text-stone-600">{panel.rationale}</p>
      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Strengths</div>
          <ul className="mt-2 space-y-2 text-sm text-stone-700">
            {panel.strengths.map((item) => (
              <li key={item}>• {item}</li>
            ))}
          </ul>
        </div>
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Gaps</div>
          <ul className="mt-2 space-y-2 text-sm text-stone-700">
            {panel.gaps.map((item) => (
              <li key={item}>• {item}</li>
            ))}
          </ul>
        </div>
      </div>
      <div className="mt-4 rounded-[18px] bg-stone-100 px-4 py-3 text-sm text-stone-700">
        <span className="font-semibold text-stone-900">Next move:</span> {panel.nextStep}
      </div>
    </div>
  );
}

function ResourceCard({
  resource,
  onSave,
}: {
  resource: LearningResource;
  onSave: (resource: LearningResource) => void;
}) {
  return (
    <article className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <SourceBadge
          trustLevel={resource.sourceType}
          label={resource.sourceType === "trusted_live" ? "Trusted live" : resource.sourceType === "official" ? "Official" : "PDF library"}
        />
        <span className="rounded-full border border-stone-900/10 px-2.5 py-1 text-[11px] font-semibold text-stone-500">
          {resource.format}
        </span>
        {resource.publishedAt ? (
          <span className="text-xs text-stone-500">{resource.publishedAt}</span>
        ) : null}
      </div>
      <h4 className="mt-3 text-lg font-semibold text-stone-900">{resource.title}</h4>
      <p className="mt-2 text-sm leading-6 text-stone-600">{resource.summary}</p>
      <div className="mt-4 grid gap-3 text-sm text-stone-700 md:grid-cols-2">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">SSCP fit</div>
          <p className="mt-1 leading-6">{resource.sscpFit}</p>
        </div>
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">CISSP bridge</div>
          <p className="mt-1 leading-6">{resource.cisspBridgeValue}</p>
        </div>
      </div>
      <div className="mt-3 rounded-[18px] bg-amber-50 px-4 py-3 text-sm text-amber-950">
        <span className="font-semibold">Strategic value:</span> {resource.strategicValue ?? resource.whyItMatters}
      </div>
      <div className="mt-4 space-y-4">
        <StudyMindmap
          title={resource.title}
          branches={[
            { title: "Summary", items: [resource.summary] },
            { title: "SSCP fit", items: [resource.sscpFit] },
            { title: "CISSP bridge", items: [resource.cisspBridgeValue] },
            { title: "Strategic value", items: [resource.strategicValue ?? resource.whyItMatters] },
          ]}
        />
        <StudyFlowDiagram
          title="Memory path"
          steps={[
            resource.summary,
            resource.whyItMatters,
            resource.sscpFit,
            resource.cisspBridgeValue,
            resource.strategicValue ?? resource.whyItMatters,
          ]}
        />
      </div>
      <div className="mt-4 flex flex-wrap items-center gap-2">
        <a
          href={resource.url}
          target="_blank"
          rel="noreferrer"
          className="rounded-full border border-stone-900 bg-stone-900 px-3 py-1.5 text-xs font-semibold text-stone-50 transition hover:bg-stone-800"
        >
          Open resource
        </a>
        <button
          type="button"
          onClick={() => onSave(resource)}
          className="rounded-full border border-stone-900/10 bg-stone-100 px-3 py-1.5 text-xs font-semibold text-stone-700 transition hover:bg-stone-200"
        >
          Save to library
        </button>
      </div>
      <div className="mt-4">
        <SscpReaderControls text={resource.readableText || resource.summary} label="resource" />
      </div>
    </article>
  );
}

function QuestionCard({
  question,
  answer,
  confidence,
  review,
  isSubmitting = false,
  showExpectedAnswer,
  onAnswerChange,
  onConfidenceChange,
  onToggleExpectedAnswer,
  onSubmit,
}: {
  question: QuestionBlueprint;
  answer: string | string[] | undefined;
  confidence: number;
  review?: DualReview;
  isSubmitting?: boolean;
  showExpectedAnswer: boolean;
  onAnswerChange: (value: string | string[]) => void;
  onConfidenceChange: (next: number) => void;
  onToggleExpectedAnswer: () => void;
  onSubmit: () => void;
}) {
  const isChoice = question.format === "single_select" || question.format === "multi_select";
  const currentSelections = Array.isArray(answer) ? answer : answer ? [answer] : [];
  return (
    <article className="rounded-[26px] border border-stone-900/10 bg-white/85 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <span className="rounded-full border border-stone-900/10 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-stone-500">
          {question.format === "single_select" || question.format === "multi_select" ? "Scenario" : question.format.replace("_", " ")}
        </span>
        <span className="rounded-full border border-amber-700/20 bg-amber-50 px-2.5 py-1 text-[11px] font-semibold text-amber-900">
          {question.difficultyLabel}
        </span>
        {question.sourceTypes.map((sourceType) => (
          <SourceBadge
            key={`${question.id}-${sourceType}`}
            trustLevel={sourceType}
            label={sourceType === "official" ? "Official" : sourceType === "trusted_live" ? "Trusted live" : "PDF library"}
          />
        ))}
      </div>
      <h4 className="mt-3 text-xl font-semibold text-stone-900">{question.title}</h4>
      <p className="mt-3 text-sm leading-7 text-stone-700">{question.prompt}</p>
      {question.scenarioContext ? (
        <div className="mt-3 rounded-[18px] bg-stone-50 px-4 py-3 text-sm text-stone-700">
          <span className="font-semibold text-stone-900">Scenario context:</span> {question.scenarioContext}
        </div>
      ) : null}
      <div className="mt-4">
        <SscpReaderControls text={`${question.title}. ${question.prompt}. ${question.scenarioContext ?? ""}`} label="question" />
      </div>
      {question.format === "multi_select" ? (
        <p className="mt-3 text-xs font-semibold uppercase tracking-[0.2em] text-amber-700">
          Select all that apply
        </p>
      ) : null}
      <div className="mt-5 space-y-3">
        {isChoice ? (
          question.options?.map((option) => {
            const checked = currentSelections.includes(option.id);
            const isCorrectOption = question.correctOptionIds?.includes(option.id) ?? false;
            const optionTone = showExpectedAnswer
              ? isCorrectOption
                ? "border-emerald-700/25 bg-emerald-50"
                : checked
                  ? "border-rose-700/20 bg-rose-50"
                  : "border-stone-900/10 bg-stone-50"
              : "border-stone-900/10 bg-stone-50";
            return (
              <label
                key={option.id}
                className={clsx(
                  "flex items-start gap-3 rounded-[18px] border px-4 py-3 text-sm text-stone-700",
                  optionTone,
                )}
              >
                <input
                  type={question.format === "single_select" ? "radio" : "checkbox"}
                  checked={checked}
                  onChange={() => {
                    if (question.format === "single_select") {
                      onAnswerChange(option.id);
                      return;
                    }
                    const next = new Set(currentSelections);
                    if (checked) next.delete(option.id);
                    else next.add(option.id);
                    onAnswerChange([...next]);
                  }}
                />
                <span>
                  <span className="font-semibold text-stone-900">{option.label}.</span>{" "}
                  {option.text}
                  {showExpectedAnswer && isCorrectOption ? (
                    <span className="ml-2 rounded-full border border-emerald-700/20 bg-white px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.16em] text-emerald-900">
                      Correct
                    </span>
                  ) : null}
                </span>
              </label>
            );
          })
        ) : (
          <textarea
            value={Array.isArray(answer) ? answer.join(", ") : answer ?? ""}
            onChange={(event) => onAnswerChange(event.target.value)}
            placeholder="Write your answer here. For stronger results, answer first as an SSCP practitioner, then add one CISSP-style sentence."
            className="min-h-[180px] w-full rounded-[22px] border border-stone-900/10 bg-stone-50 px-4 py-4 text-sm leading-7 text-stone-900 outline-none transition focus:border-stone-900/25 focus:bg-white"
          />
        )}
      </div>
      <div className="mt-5 grid gap-3 md:grid-cols-[1fr_auto_auto] md:items-end">
        <label className="block">
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Confidence</div>
          <input
            type="range"
            min={0}
            max={100}
            value={confidence}
            onChange={(event) => onConfidenceChange(Number(event.target.value))}
            className="mt-2 w-full"
          />
          <div className="mt-1 text-sm text-stone-600">{confidence}/100</div>
        </label>
        <button
          type="button"
          onClick={onSubmit}
          disabled={isSubmitting}
          className={clsx(
            "rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800",
            isSubmitting && "cursor-not-allowed opacity-60",
          )}
        >
          {isSubmitting ? "Evaluating..." : "Evaluate answer"}
        </button>
        <button
          type="button"
          onClick={onToggleExpectedAnswer}
          className="rounded-full border border-stone-900/10 bg-stone-100 px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-200"
        >
          {showExpectedAnswer ? "Hide expected answer" : "Show expected answer"}
        </button>
      </div>
      {showExpectedAnswer ? <ExpectedAnswerPanel question={question} /> : null}
      {review ? (
        <div className="mt-6 space-y-4 rounded-[22px] border border-stone-900/10 bg-[linear-gradient(180deg,rgba(249,246,241,0.95),rgba(255,255,255,0.96))] p-5">
          <div className="flex flex-wrap items-center gap-2">
            <span className="rounded-full border border-stone-900/10 px-2.5 py-1 text-[11px] font-semibold text-stone-600">
              Confidence gap {review.confidenceGap}
            </span>
            <span className="rounded-full border border-stone-900/10 px-2.5 py-1 text-[11px] font-semibold text-stone-600">
              {review.correctness}
            </span>
            <span className="rounded-full border border-stone-900/10 px-2.5 py-1 text-[11px] font-semibold text-stone-600">
              {review.confidenceLevel} source confidence
            </span>
          </div>
          <SscpReaderControls
            text={`${review.bestAnswerRationale} ${review.thinkingCorrection} ${review.sscpTakeaway} ${review.cisspTakeaway}`}
            label="review"
          />
          <div className="grid gap-4 xl:grid-cols-2">
            <ReviewPanelCard title="SSCP Review" panel={review.sscpReview} />
            <ReviewPanelCard title="CISSP Review" panel={review.cisspReview} />
          </div>
          <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <div className="rounded-[20px] bg-white px-4 py-4 text-sm leading-7 text-stone-700">
              <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Best-answer logic</div>
              <p className="mt-2">{review.bestAnswerRationale}</p>
              <div className="mt-4 rounded-[16px] bg-stone-50 px-4 py-3">
                <span className="font-semibold text-stone-900">Thinking correction:</span> {review.thinkingCorrection}
              </div>
            </div>
            <div className="rounded-[20px] bg-white px-4 py-4 text-sm leading-7 text-stone-700">
              <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Takeaways</div>
              <div className="mt-2 rounded-[16px] bg-stone-50 px-4 py-3">
                <span className="font-semibold text-stone-900">SSCP:</span> {review.sscpTakeaway}
              </div>
              <div className="mt-3 rounded-[16px] bg-amber-50 px-4 py-3 text-amber-950">
                <span className="font-semibold">CISSP:</span> {review.cisspTakeaway}
              </div>
              <ul className="mt-4 space-y-2">
                {review.distractorWarnings.map((item) => (
                  <li key={item}>• {item}</li>
                ))}
              </ul>
            </div>
          </div>
          <div className="rounded-[18px] bg-stone-900 px-4 py-3 text-sm text-stone-100">
            <span className="font-semibold">Strategic takeaway:</span> {question.strategicTakeaway}
          </div>
        </div>
      ) : null}
    </article>
  );
}

export default function SscpCoach() {
  const searchParams = useSearchParams();
  const [isHydrated, setIsHydrated] = useState(false);
  const [workspace, setWorkspace] = useState<Workspace>("plan");
  const [profile, setProfile] = useState<LearnerProfile>(makeDefaultProfile);
  const [mastery, setMastery] = useState<MasterySnapshot>(() => normalizeMastery(createEmptyMasterySnapshot()));
  const [notes, setNotes] = useState<ImportedNoteChunk[]>([]);
  const [savedResources, setSavedResources] = useState<LearningResource[]>([]);
  const [captures, setCaptures] = useState<ExtensionCapture[]>([]);
  const [captureAid, setCaptureAid] = useState<{ captureId: string; aid: CaptureStudyAid } | null>(null);
  const [lessonRedirect, setLessonRedirect] = useState<string | null>(null);
  const [plan, setPlan] = useState<StudySprintPlan | null>(null);
  const [lesson, setLesson] = useState<TeachResponse | null>(null);
  const [drill, setDrill] = useState<DrillResponse | null>(null);
  const [mock, setMock] = useState<MockResponse | null>(null);
  const [resources, setResources] = useState<{ summary: string; curated: LearningResource[]; live: LearningResource[] }>({
    summary: "Validated study paths and PDF overlays will appear here.",
    curated: [],
    live: [],
  });
  const [selectedDomain, setSelectedDomain] = useState<SscpDomainId>("security-concepts-practices");
  const [topicHint, setTopicHint] = useState("zero trust, detection engineering, incident response");
  const deferredTopicHint = useDeferredValue(topicHint);
  const [answers, setAnswers] = useState<Record<string, string | string[]>>({});
  const [confidence, setConfidence] = useState<Record<string, number>>({});
  const [reviews, setReviews] = useState<Record<string, DualReview>>({});
  const [revealedAnswers, setRevealedAnswers] = useState<Record<string, boolean>>({});
  const [sessionStartedAt, setSessionStartedAt] = useState<string | null>(null);
  const [status, setStatus] = useState("Tutor ready.");
  const [busyActions, setBusyActions] = useState<Partial<Record<BusyActionKey, boolean>>>({});
  const [isPending, startUiTransition] = useTransition();

  useEffect(() => {
    setIsHydrated(true);
  }, []);

  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const parsed = JSON.parse(raw) as Partial<PersistedCoachState>;
      if (parsed.profile) setProfile(parsed.profile);
      if (parsed.mastery) setMastery(normalizeMastery(parsed.mastery));
      if (parsed.notes) setNotes(parsed.notes);
      if (parsed.savedResources) setSavedResources(parsed.savedResources);
    } catch {
      // Ignore storage hydration errors and continue with defaults.
    }
  }, []);

  useEffect(() => {
    const payload: PersistedCoachState = {
      profile,
      mastery,
      notes,
      savedResources,
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
  }, [profile, mastery, notes, savedResources]);

  useEffect(() => {
    void loadCaptures();
  }, []);

  useEffect(() => {
    const requestedWorkspace = searchParams.get("workspace");
    if (
      requestedWorkspace &&
      ["plan", "learn", "drill", "resources", "library"].includes(requestedWorkspace)
    ) {
      setWorkspace(requestedWorkspace as Workspace);
    }
  }, [searchParams]);

  useEffect(() => {
    const captureId = searchParams.get("captureId");
    if (!captureId || !captures.length) return;
    const target = captures.find((capture) => capture.id === captureId);
    if (!target) return;
    setWorkspace("library");
    setCaptureAid({ captureId: target.id, aid: buildCaptureStudyAid(target) });
    if (searchParams.get("intent") === "quiz") {
      setStatus(`Capture ready for study: ${target.title}`);
    }
  }, [captures, searchParams]);

  const filteredResources = useMemo(() => {
    const haystack = deferredTopicHint.toLowerCase().trim();
    const combined = [...resources.live, ...resources.curated];
    if (!haystack) return combined;
    return combined.filter((resource) =>
      `${resource.title} ${resource.summary} ${resource.whyItMatters}`.toLowerCase().includes(haystack),
    );
  }, [deferredTopicHint, resources]);
  const activeQuestions: QuestionBlueprint[] = mock?.questions ?? drill?.questions ?? [];
  const selectedDomainMeta = SSCP_DOMAINS.find((domain) => domain.id === selectedDomain) ?? SSCP_DOMAINS[0];
  const isPlanLoading = !!busyActions.plan;
  const isLessonLoading = !!busyActions.lesson;
  const isResourcesLoading = !!busyActions.resources;
  const isDrillLoading = !!busyActions.drill;
  const isMockLoading = !!busyActions.mock;
  const isNotesImporting = !!busyActions.notes;
  const isCapturesLoading = !!busyActions.captures;
  const anyActionBusy = isPending || Object.keys(busyActions).length > 0;

  function setActionBusy(actionKey: BusyActionKey, isBusy: boolean) {
    setBusyActions((current) => {
      if (isBusy) {
        return { ...current, [actionKey]: true };
      }

      const next = { ...current };
      delete next[actionKey];
      return next;
    });
  }

  async function runAction(actionKey: BusyActionKey, actionLabel: string, task: () => Promise<void>) {
    setActionBusy(actionKey, true);
    try {
      await task();
    } catch (error: any) {
      setStatus(error?.message ?? `${actionLabel} failed.`);
    } finally {
      setActionBusy(actionKey, false);
    }
  }

  async function loadCaptures() {
    setActionBusy("captures", true);
    try {
      const data = await fetchJson<{ captures: ExtensionCapture[] }>("/api/sscp/extension/captures", {
        method: "GET",
      });
      startUiTransition(() => setCaptures(data.captures));
    } catch {
      // Keep the page usable if capture polling fails.
    } finally {
      setActionBusy("captures", false);
    }
  }

  async function importNotes(force = false) {
    await runAction("notes", "Import notes", async () => {
      setWorkspace("library");
      setStatus("Importing the local SSCP/CISSP PDF study corpus...");
      const data = await fetchJson<{ chunks: ImportedNoteChunk[] }>("/api/sscp/notes/import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ force }),
      });
      startUiTransition(() => {
        setNotes(data.chunks);
        setWorkspace("library");
        setStatus(`Imported ${data.chunks.length} PDF chunks for supplemental lesson and drill reinforcement.`);
      });
    });
  }

  async function generatePlan() {
    await runAction("plan", "Generate sprint", async () => {
      setWorkspace("plan");
      setStatus("Building your next 7-day sprint...");
      const data = await fetchJson<{ plan: StudySprintPlan }>("/api/sscp/plan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ profile, mastery }),
      });
      startUiTransition(() => {
        setPlan(data.plan);
        setWorkspace("plan");
        setStatus("Study sprint updated.");
      });
    });
  }

  async function loadLesson(domainId: SscpDomainId) {
    await runAction("lesson", "Build lesson", async () => {
      setSelectedDomain(domainId);
      setLesson(null);
      setLessonRedirect(null);
      setWorkspace("learn");
      setStatus(`Building a grounded lesson for ${SSCP_DOMAINS.find((domain) => domain.id === domainId)?.title}...`);
      const data = await fetchJson<TeachResponse>("/api/sscp/teach", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ domainId }),
      });
      startUiTransition(() => {
        setLesson(data);
        setStatus("Lesson ready.");
      });
    });
  }

  async function loadResources(domainId: SscpDomainId) {
    await runAction("resources", "Refresh resources", async () => {
      setWorkspace("resources");
      setStatus("Loading validated study paths and PDF overlays...");
      setResources((current) => ({
        ...current,
        summary: "Refreshing trusted study paths and related PDF overlays for the selected domain...",
      }));
      const data = await fetchJson<{ summary: string; curated: LearningResource[]; live: LearningResource[] }>("/api/sscp/resources", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ domainIds: [domainId], topicHint }),
      });
      startUiTransition(() => {
        setResources(data);
        setWorkspace("resources");
        setStatus("Resources refreshed.");
      });
    });
  }

  async function generateDrill(mode: "mixed" | "multiple_choice" | "short_answer" | "scenario") {
    await runAction("drill", "Generate drill", async () => {
      setWorkspace("drill");
      setDrill(null);
      setMock(null);
      setAnswers({});
      setConfidence({});
      setReviews({});
      setRevealedAnswers({});
      setSessionStartedAt(new Date().toISOString());
      setStatus("Generating a new drill set...");
      const data = await fetchJson<DrillResponse>("/api/sscp/drill", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          domainIds: [selectedDomain],
          mode,
          count: mode === "scenario" ? 3 : 4,
          difficulty: mode === "scenario" ? "bridge" : "pressure",
        }),
      });
      startUiTransition(() => {
        setDrill(data);
        setStatus("Drill ready.");
      });
    });
  }

  async function generateMock(length: "mini" | "full") {
    await runAction("mock", "Generate mock", async () => {
      setWorkspace("drill");
      setMock(null);
      setDrill(null);
      setAnswers({});
      setConfidence({});
      setReviews({});
      setRevealedAnswers({});
      setSessionStartedAt(new Date().toISOString());
      setStatus(`Generating your ${length} mock...`);
      const data = await fetchJson<MockResponse>("/api/sscp/mock", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ length }),
      });
      startUiTransition(() => {
        setMock(data);
        setStatus(`${length === "full" ? "Full" : "Mini"} mock ready.`);
      });
    });
  }

  function updateMasteryAfterReview(question: QuestionBlueprint, review: DualReview) {
    setMastery((current) => {
      const nextDomains = current.domains.map((entry) => {
        if (!question.domainIds.includes(entry.domainId)) return entry;
        const nextScore = Math.round(entry.score * 0.7 + review.sscpReview.score * 0.3);
        const nextConfidence = Math.round(entry.confidence * 0.7 + (100 - Math.abs(review.confidenceGap)) * 0.3);
        return {
          ...entry,
          score: Math.max(0, Math.min(100, nextScore)),
          confidence: Math.max(0, Math.min(100, nextConfidence)),
          attempts: entry.attempts + 1,
          lastReviewedAt: new Date().toISOString(),
        };
      });
      return normalizeMastery({
        ...current,
        confidenceCalibration: Math.max(0, Math.min(100, 100 - Math.abs(review.confidenceGap))),
        recentMocks: current.recentMocks,
        domains: nextDomains,
      });
    });
  }

  async function evaluateQuestion(question: QuestionBlueprint) {
    const currentAnswer = answers[question.id];
    if (!currentAnswer || (Array.isArray(currentAnswer) && currentAnswer.length === 0)) {
      setStatus("Add an answer before requesting a review.");
      return;
    }
    const attempt: QuestionAttempt = {
      questionId: question.id,
      answer: currentAnswer,
      confidence: confidence[question.id] ?? 55,
    };
    await runAction(`evaluate:${question.id}`, "Evaluate answer", async () => {
      setStatus(`Evaluating ${question.title}...`);
      const review = await fetchJson<DualReview>("/api/sscp/evaluate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, attempt }),
      });
      startUiTransition(() => {
        setReviews((current) => ({ ...current, [question.id]: review }));
        setRevealedAnswers((current) => ({ ...current, [question.id]: true }));
        updateMasteryAfterReview(question, review);
        setStatus("Dual review complete.");
      });
    });
  }

  function restartChronometer() {
    if (!activeQuestions.length) {
      setStatus("Start a drill or mock before restarting the timer.");
      return;
    }

    startTransition(() => {
      setSessionStartedAt(new Date().toISOString());
      setStatus("Chronometer restarted.");
    });
  }

  function saveResource(resource: LearningResource) {
    startTransition(() => {
      setSavedResources((current) => {
        if (current.some((item) => item.url === resource.url)) return current;
        return [resource, ...current];
      });
      setStatus(`Saved ${resource.title} to your library.`);
    });
  }

  function openCaptureStudyAid(capture: ExtensionCapture) {
    startTransition(() => {
      setCaptureAid({ captureId: capture.id, aid: buildCaptureStudyAid(capture) });
      setWorkspace("library");
      setStatus(`Study aid ready for capture: ${capture.title}`);
    });
  }

  return (
    <main
      data-coach-ready={isHydrated ? "true" : "false"}
      className="min-h-screen bg-[radial-gradient(circle_at_top_left,rgba(191,146,79,0.18),transparent_28%),linear-gradient(180deg,#f6f0e8_0%,#efe6d8_100%)] text-stone-950"
    >
      <div className="mx-auto max-w-[1500px] px-4 py-6 md:px-6 md:py-8">
        <div className="grid gap-6 xl:grid-cols-[290px_minmax(0,1fr)]">
          <aside className={clsx(surfaceClass("cream"), "h-fit p-5 md:p-6 xl:sticky xl:top-6")}>
            <div className="text-xs uppercase tracking-[0.28em] text-stone-500">Security mastery</div>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight text-stone-950">
              SSCP first. CISSP next.
            </h1>
            <p className="mt-3 text-sm leading-7 text-stone-600">
              This tutor keeps official SSCP/CISSP framing first, adds trusted study references, and uses your local
              SSCP and CISSP PDFs as reinforcement while pushing every answer through both an SSCP and CISSP review.
            </p>
            <div className="mt-5 flex flex-wrap gap-3">
              <MetricPill label="SSCP readiness" value={`${mastery.overallReadiness}`} />
              <MetricPill label="CISSP bridge" value={`${mastery.cisspBridgeReadiness}`} accent="text-amber-700" />
            </div>
            <div className="mt-6 space-y-3">
              <WorkspaceButton active={workspace === "plan"} onClick={() => setWorkspace("plan")} title="Plan" blurb="Adaptive sprint, readiness, and pressure tasks." />
              <WorkspaceButton active={workspace === "learn"} onClick={() => setWorkspace("learn")} title="Learn" blurb="Grounded lessons, PDF overlays, and narrated study." />
              <WorkspaceButton active={workspace === "drill"} onClick={() => setWorkspace("drill")} title="Drill" blurb="Mixed-format questions, mock exams, and dual review." />
              <WorkspaceButton active={workspace === "resources"} onClick={() => setWorkspace("resources")} title="Resources" blurb="Trusted study paths, guides, and PDF excerpts." />
              <WorkspaceButton active={workspace === "library"} onClick={() => setWorkspace("library")} title="Library" blurb="Imported PDF chunks, saved resources, and extension captures." />
            </div>
            <div className="mt-6 rounded-[22px] border border-stone-900/10 bg-white/70 p-4">
              <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Source policy</div>
              <div className="mt-3 space-y-3">
                {Object.entries(SOURCE_POLICY).map(([key, description]) => (
                  <div key={key}>
                    <SourceBadge
                      trustLevel={key as SourceTrustLevel}
                      label={key === "trusted_live" ? "Trusted live" : key === "user_notes" ? "PDF library" : "Official"}
                    />
                    <p className="mt-1 text-xs leading-6 text-stone-600">{description}</p>
                  </div>
                ))}
              </div>
            </div>
          </aside>
          <section className="space-y-6">
            <SectionShell
              title="Adaptive SSCP Tutor with CISSP Bridge"
              subtitle="Use the main app for grounded lessons, drills, dual reviews, narration, trusted study paths, and PDF-based reinforcement. Use the browser extension companion to capture your own notes while you browse."
              tone="ink"
              actions={
                <>
                  <button
                    type="button"
                    disabled={isNotesImporting}
                    onClick={() => void importNotes(false)}
                    className={clsx(
                      "rounded-full border border-stone-50/15 bg-stone-50 px-4 py-2 text-sm font-semibold text-stone-900 transition hover:bg-white",
                      isNotesImporting && "cursor-not-allowed opacity-60",
                    )}
                  >
                    {isNotesImporting ? "Importing PDFs..." : "Import study PDFs"}
                  </button>
                  <a
                    href="#extension-companion"
                    className="rounded-full border border-stone-50/20 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-50/10"
                  >
                    Browser extension
                  </a>
                </>
              }
            >
              <div className="grid gap-5 lg:grid-cols-[minmax(0,1.35fr)_minmax(0,0.95fr)]">
                <div className="rounded-[24px] border border-stone-50/10 bg-white/6 p-5">
                  <div className="text-xs uppercase tracking-[0.22em] text-stone-300">Live status</div>
                  <p className="mt-3 text-sm leading-7 text-stone-100">{status}</p>
                  {anyActionBusy ? (
                    <div className="mt-2 text-xs uppercase tracking-[0.18em] text-amber-300">
                      Updating workspace...
                    </div>
                  ) : null}
                  <div className="mt-4 flex flex-wrap gap-3">
                    <MetricPill label="Notes chunks" value={`${notes.length}`} />
                    <MetricPill label="Saved resources" value={`${savedResources.length}`} />
                    <MetricPill label="Extension captures" value={`${captures.length}`} />
                  </div>
                </div>
                <div className="rounded-[24px] border border-stone-50/10 bg-white/6 p-5">
                  <div className="text-xs uppercase tracking-[0.22em] text-stone-300">Quick actions</div>
                  <div className="mt-4 grid gap-3">
                    <button
                      type="button"
                      disabled={isPlanLoading}
                      onClick={() => void generatePlan()}
                      className={clsx(
                        "rounded-[18px] border border-stone-50/20 bg-stone-50 px-4 py-3 text-left text-sm font-semibold text-stone-900 transition hover:bg-white",
                        isPlanLoading && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isPlanLoading ? "Refreshing adaptive sprint..." : "Refresh adaptive sprint"}
                    </button>
                    <button
                      type="button"
                      disabled={isLessonLoading}
                      onClick={() => void loadLesson(selectedDomain)}
                      className={clsx(
                        "rounded-[18px] border border-stone-50/20 px-4 py-3 text-left text-sm font-semibold text-stone-50 transition hover:bg-stone-50/10",
                        isLessonLoading && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isLessonLoading ? "Building grounded lesson..." : "Build grounded lesson for current domain"}
                    </button>
                    <button
                      type="button"
                      disabled={isDrillLoading || isMockLoading}
                      onClick={() => void generateDrill("mixed")}
                      className={clsx(
                        "rounded-[18px] border border-stone-50/20 px-4 py-3 text-left text-sm font-semibold text-stone-50 transition hover:bg-stone-50/10",
                        (isDrillLoading || isMockLoading) && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isDrillLoading ? "Starting mixed drill..." : "Start mixed-format drill"}
                    </button>
                  </div>
                </div>
              </div>
            </SectionShell>

            <SectionShell
              title="Control deck"
              subtitle="Tune the tutor before you study. Pick the domain, adjust your time commitment, and decide what the next action should pressure."
              actions={
                <>
                  <button
                    type="button"
                    disabled={isLessonLoading}
                    onClick={() => void loadLesson(selectedDomain)}
                    className={clsx(
                      "rounded-full border border-stone-900/10 bg-stone-100 px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-200",
                      isLessonLoading && "cursor-not-allowed opacity-60",
                    )}
                  >
                    {isLessonLoading ? "Refreshing lesson..." : "Refresh lesson"}
                  </button>
                  <button
                    type="button"
                    disabled={isResourcesLoading}
                    onClick={() => void loadResources(selectedDomain)}
                    className={clsx(
                      "rounded-full border border-stone-900/10 bg-stone-100 px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-200",
                      isResourcesLoading && "cursor-not-allowed opacity-60",
                    )}
                  >
                    {isResourcesLoading ? "Refreshing resources..." : "Refresh resources"}
                  </button>
                </>
              }
            >
              <div className="grid gap-4 lg:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
                <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                  <label className="block text-xs uppercase tracking-[0.22em] text-stone-500">
                    Current domain
                  </label>
                  <select
                    value={selectedDomain}
                    onChange={(event) => setSelectedDomain(event.target.value as SscpDomainId)}
                    className="mt-3 w-full rounded-[18px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none transition focus:border-stone-900/30"
                  >
                    {SSCP_DOMAINS.map((domain) => (
                      <option key={domain.id} value={domain.id}>
                        {domain.title}
                      </option>
                    ))}
                  </select>
                  <div className="mt-4 text-sm leading-7 text-stone-600">
                    {selectedDomainMeta.summary}
                  </div>
                </div>
                <div className="grid gap-4 md:grid-cols-2">
                  <label className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                    <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                      Weekly hours
                    </div>
                    <input
                      type="number"
                      min={1}
                      max={40}
                      value={profile.weeklyHours}
                      onChange={(event) =>
                        setProfile((current) => ({
                          ...current,
                          weeklyHours: Number(event.target.value) || 1,
                        }))
                      }
                      className="mt-3 w-full rounded-[18px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none transition focus:border-stone-900/30"
                    />
                  </label>
                  <label className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                    <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                      Current role
                    </div>
                    <input
                      type="text"
                      value={profile.currentRole}
                      onChange={(event) =>
                        setProfile((current) => ({
                          ...current,
                          currentRole: event.target.value,
                        }))
                      }
                      className="mt-3 w-full rounded-[18px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none transition focus:border-stone-900/30"
                    />
                  </label>
                </div>
              </div>
            </SectionShell>

            {workspace === "plan" ? (
              <SectionShell
                title="Adaptive 7-day sprint"
                subtitle="The planner focuses on weak domains first, then adds deliberate pressure and a CISSP bridge task so confidence does not outpace understanding."
                actions={
                  <button
                    type="button"
                    disabled={isPlanLoading}
                    onClick={() => void generatePlan()}
                    className={clsx(
                      "rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800",
                      isPlanLoading && "cursor-not-allowed opacity-60",
                    )}
                  >
                    {isPlanLoading ? "Generating sprint..." : "Generate sprint"}
                  </button>
                }
              >
                {plan ? (
                  <div className="space-y-5">
                    <div className="grid gap-4 xl:grid-cols-[minmax(0,1.15fr)_minmax(0,0.85fr)]">
                      <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                        <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                          Plan summary
                        </div>
                        <p className="mt-3 text-sm leading-7 text-stone-700">{plan.summary}</p>
                        <div className="mt-4 rounded-[18px] bg-white px-4 py-3 text-sm text-stone-700">
                          <span className="font-semibold text-stone-900">Pressure note:</span>{" "}
                          {plan.pressureNote}
                        </div>
                      </div>
                      <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                        <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                          Readiness snapshot
                        </div>
                        <div className="mt-4 grid gap-3 md:grid-cols-2">
                          <MetricPill label="Overall" value={`${plan.readiness.overallReadiness}`} />
                          <MetricPill label="Bridge" value={`${plan.readiness.cisspBridgeReadiness}`} accent="text-amber-700" />
                          <MetricPill label="Calibration" value={`${plan.readiness.confidenceCalibration}`} />
                          <MetricPill
                            label="Mocks logged"
                            value={`${plan.readiness.recentMocks.length}`}
                          />
                        </div>
                      </div>
                    </div>
                    <div className="grid gap-4">
                      {plan.tasks.map((task) => (
                        <div
                          key={task.id}
                          className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5"
                        >
                          <div className="flex flex-wrap items-center gap-2">
                            <span className="rounded-full border border-stone-900/10 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-stone-500">
                              {task.phase}
                            </span>
                            <span className="rounded-full border border-amber-700/20 bg-amber-50 px-2.5 py-1 text-[11px] font-semibold text-amber-900">
                              {task.intensity}
                            </span>
                            <span className="text-xs text-stone-500">{task.durationMinutes} min</span>
                          </div>
                          <h3 className="mt-3 text-lg font-semibold text-stone-900">{task.title}</h3>
                          <p className="mt-2 text-sm leading-7 text-stone-600">{task.description}</p>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : (
                  <div className="rounded-[24px] border border-dashed border-stone-900/20 bg-stone-50/70 p-6 text-sm leading-7 text-stone-600">
                    Generate a sprint to get your week of study tasks, pressure drills, and bridge work.
                  </div>
                )}
              </SectionShell>
            ) : null}

            {workspace === "learn" ? (
              <SectionShell
                title="Grounded learning workspace"
                subtitle="Learn from the official domain framing first, then use your imported note chunks as reinforcement. Every lesson keeps the trust order visible."
                actions={
                  <button
                    type="button"
                    disabled={isLessonLoading}
                    onClick={() => void loadLesson(selectedDomain)}
                    className={clsx(
                      "rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800",
                      isLessonLoading && "cursor-not-allowed opacity-60",
                    )}
                  >
                    {isLessonLoading ? "Building lesson..." : "Build lesson"}
                  </button>
                }
              >
                {lesson ? (
                  <div className="space-y-5">
                    <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                      <div className="flex flex-wrap items-center gap-2">
                        {lesson.sourceTypes.map((sourceType) => (
                          <SourceBadge
                            key={`lesson-${sourceType}`}
                            trustLevel={sourceType}
                            label={sourceType === "official" ? "Official" : sourceType === "trusted_live" ? "Trusted live" : "PDF library"}
                          />
                        ))}
                      </div>
                      <h3 className="mt-3 text-xl font-semibold text-stone-900">
                        {lesson.domain.title}
                      </h3>
                      <p className="mt-3 text-sm leading-7 text-stone-700">{lesson.lessonSummary}</p>
                      <div className="mt-4">
                        <SscpReaderControls
                          text={`${lesson.domain.title}. ${lesson.lessonSummary}. ${lesson.lessonSections
                            .map((section) => `${section.title}. ${section.body}`)
                            .join(" ")} Study tips. ${lesson.studyTips.join(" ")} Strategic lens. ${lesson.strategicLens.leadershipPrompt}`}
                          label="lesson"
                        />
                      </div>
                      <div className="mt-4 flex flex-wrap gap-2 text-xs text-stone-500">
                        {lesson.citations.map((citation) => (
                          <span
                            key={citation.id}
                            className="rounded-full border border-stone-900/10 bg-white px-3 py-1"
                          >
                            {citation.sourceName}
                            {citation.publishedAt ? ` · ${citation.publishedAt}` : ""}
                          </span>
                        ))}
                      </div>
                    </div>
                    <div className="grid gap-4 xl:grid-cols-[minmax(0,1.08fr)_minmax(0,0.92fr)]">
                      <div className="space-y-4">
                        <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Guided lesson flow</div>
                          <div className="mt-4 space-y-3">
                            {lesson.lessonSections.map((section, index) => (
                              <div
                                key={section.title}
                                className="rounded-[20px] border border-stone-900/10 bg-stone-50/80 px-4 py-4"
                              >
                                <div className="text-[11px] uppercase tracking-[0.18em] text-stone-500">
                                  Step {index + 1}
                                </div>
                                <h4 className="mt-2 text-lg font-semibold text-stone-900">{section.title}</h4>
                                <p className="mt-3 text-sm leading-7 text-stone-600">{section.body}</p>
                              </div>
                            ))}
                          </div>
                        </div>
                        <WorkedExampleStudio examples={lesson.workedExamples} />
                        <ScenarioStudio
                          scenarios={lesson.lessonScenarios}
                          onLaunchDrill={() => void generateDrill("scenario")}
                        />
                      </div>
                      <div className="space-y-4">
                        <StrategicLensCard lens={lesson.strategicLens} />
                        <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Study tips</div>
                          <ul className="mt-4 space-y-2 text-sm leading-7 text-stone-700">
                            {lesson.studyTips.map((tip) => (
                              <li key={tip}>• {tip}</li>
                            ))}
                          </ul>
                        </div>
                        <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Glossary anchors</div>
                          <div className="mt-3 flex flex-wrap gap-2">
                            {lesson.glossary.map((item) => (
                              <span
                                key={item}
                                className="rounded-full border border-stone-900/10 px-3 py-1.5 text-xs font-semibold text-stone-700"
                              >
                                {item}
                              </span>
                            ))}
                          </div>
                        </div>
                        <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                            Notes overlay
                          </div>
                          <p className="mt-2 text-sm leading-6 text-stone-600">
                            These PDF excerpts are your local study corpus. Use them for reinforcement, examples, and recall after you understand the core control move.
                          </p>
                          <div className="mt-4 space-y-3">
                            {lesson.noteReferences.length ? (
                              lesson.noteReferences.map((note) => (
                                <div key={note.id} className="rounded-[18px] bg-stone-50 px-4 py-3">
                                  <div className="text-xs font-semibold uppercase tracking-[0.18em] text-amber-800">
                                    PDF study reference
                                  </div>
                                  <div className="mt-1 text-sm font-semibold text-stone-900">
                                    {note.fileName} · {note.sectionLabel}
                                  </div>
                                  <p className="mt-2 text-sm leading-6 text-stone-600">
                                    {note.excerpt}
                                  </p>
                                </div>
                              ))
                            ) : (
                              <div className="rounded-[18px] bg-stone-50 px-4 py-3 text-sm text-stone-600">
                                Import the local study PDFs to pull chapter chunks into this lesson.
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                    <FlashcardDeck cards={lesson.flashcards} />
                    <CheckpointLab
                      checkpoints={lesson.checkpointQuestions}
                      onMiss={(message) => {
                        setLessonRedirect(message);
                        setStatus("Checkpoint missed. Tighten the lesson before moving on.");
                      }}
                    />
                    {lessonRedirect ? (
                      <div className="rounded-[24px] border border-rose-700/20 bg-rose-50/80 p-5 text-sm leading-7 text-rose-900">
                        <span className="font-semibold">Targeted reinforcement:</span> {lessonRedirect}
                      </div>
                    ) : null}
                    <StudyMindmap
                      title={lesson.domain.title}
                      branches={[
                        {
                          title: "Mapped objectives",
                          items: lesson.objectiveFocus.map((objective) => objective.title),
                        },
                        {
                          title: "Glossary anchors",
                          items: lesson.glossary.slice(0, 6),
                        },
                        { title: "Study tips", items: lesson.studyTips },
                        {
                          title: "CISSP bridge",
                          items: [lesson.strategicLens.architectureTradeoff, lesson.strategicLens.businessImpact],
                        },
                      ]}
                    />
                    <StudyFlowDiagram
                      title="How to memorize this domain"
                      steps={[
                        "Start with the mapped objective wording shown in this lesson.",
                        "Anchor the objective to one control or process.",
                        "Use the PDF study corpus as reinforcement and retrieval practice material.",
                        "Pressure-test the concept through a scenario.",
                        "Translate the same answer into strategic language.",
                      ]}
                    />
                    <div className="grid gap-4">
                      {lesson.diagramSpecs.map((spec) => (
                        <StudyDiagramExplorer key={spec.id} spec={spec} />
                      ))}
                    </div>
                  </div>
                ) : isLessonLoading ? (
                  <div className="space-y-4">
                      <LoadingPanel
                        eyebrow="Grounded lesson"
                        title="Building the guided lesson flow"
                        body="The tutor is grounding this domain in official framing, layering in trusted study references, and then adding PDF reinforcement, scenarios, recall prompts, and the CTO-growth lens."
                      />
                    <div className="grid gap-4 xl:grid-cols-2">
                      <LoadingPanel
                        eyebrow="Flashcard deck"
                        title="Creating recall prompts"
                        body="Key concepts are being turned into memory cards with fast front-back recall cues."
                      />
                      <LoadingPanel
                        eyebrow="Checkpoint lab"
                        title="Preparing challenge questions"
                        body="Checkpoint prompts are being shaped to push you from theory into operational and strategic application."
                      />
                    </div>
                    <div className="grid gap-4 xl:grid-cols-2">
                      <LoadingPanel
                        eyebrow="Worked example"
                        title="Generating applied walkthroughs"
                        body="The tutor is pairing the concept with control-driven examples and failure modes you should recognize under pressure."
                      />
                      <LoadingPanel
                        eyebrow="Diagram / mindmap"
                        title="Mapping relationships"
                        body="Interactive visuals are being prepared so you can click through dependencies, tradeoffs, and scenario flow."
                      />
                    </div>
                  </div>
                ) : (
                  <div className="rounded-[24px] border border-dashed border-stone-900/20 bg-stone-50/70 p-6 text-sm leading-7 text-stone-600">
                    Build a lesson for the currently selected domain to see grounded notes, glossary terms, and the source hierarchy.
                  </div>
                )}
              </SectionShell>
            ) : null}

            {workspace === "drill" ? (
              <SectionShell
                title="Pressure drills and mock exams"
                subtitle="Choose a mode, answer with a confidence score, and let the tutor review your response from both an SSCP and CISSP perspective."
                actions={
                  <>
                    <button
                      type="button"
                      disabled={isDrillLoading || isMockLoading}
                      onClick={() => void generateDrill("mixed")}
                      className={clsx(
                        "rounded-full border border-stone-900/10 bg-stone-100 px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-200",
                        (isDrillLoading || isMockLoading) && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isDrillLoading ? "Loading drill..." : "Mixed drill"}
                    </button>
                    <button
                      type="button"
                      disabled={isDrillLoading || isMockLoading}
                      onClick={() => void generateDrill("scenario")}
                      className={clsx(
                        "rounded-full border border-stone-900/10 bg-stone-100 px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-200",
                        (isDrillLoading || isMockLoading) && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isDrillLoading ? "Loading scenario..." : "Scenario drill"}
                    </button>
                    <button
                      type="button"
                      disabled={isMockLoading || isDrillLoading}
                      onClick={() => void generateMock("mini")}
                      className={clsx(
                        "rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800",
                        (isMockLoading || isDrillLoading) && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isMockLoading ? "Building mock..." : "Mini mock"}
                    </button>
                  </>
                }
              >
                {mock ? (
                  <div className="mb-5 rounded-[24px] border border-amber-700/20 bg-amber-50/80 p-5">
                    <div className="text-xs uppercase tracking-[0.22em] text-amber-800">Mock guidance</div>
                    <p className="mt-3 text-sm leading-7 text-amber-950">{mock.guidance}</p>
                    <div className="mt-4 flex flex-wrap gap-3">
                      <MetricPill label="Items" value={`${mock.questions.length}`} />
                      <MetricPill label="Duration" value={`${mock.durationMinutes} min`} />
                    </div>
                  </div>
                ) : null}
                {activeQuestions.length ? (
                  <div className="space-y-5">
                    <div className="grid gap-4 xl:grid-cols-[minmax(0,0.88fr)_minmax(0,1.12fr)]">
                      <ChronometerCard
                        startedAt={sessionStartedAt}
                        durationMinutes={mock?.durationMinutes}
                        label={mock ? `${mock.length === "full" ? "Full mock" : "Mini mock"} chronometer` : "Drill chronometer"}
                        onRestart={restartChronometer}
                      />
                      <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                        <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                          How evaluation works
                        </div>
                        <p className="mt-3 text-sm leading-7 text-stone-700">
                          Choice questions are checked against the expected option IDs. Short-answer and scenario items
                          are compared to the ideal answer, the answer guidance, and the key phrases tied to the
                          mapped objective. Then the tutor produces two reviews: one for SSCP correctness and one for
                          broader CISSP-style reasoning.
                        </p>
                        <p className="mt-3 text-sm leading-7 text-stone-600">
                          You can now reveal the expected answer at any time. After you submit, the tutor will also
                          open that answer panel automatically so you can compare your thinking immediately.
                        </p>
                      </div>
                    </div>
                    {activeQuestions.slice(0, mock?.length === "full" ? 12 : activeQuestions.length).map((question) => (
                      <QuestionCard
                        key={question.id}
                        question={question}
                        answer={answers[question.id]}
                        confidence={confidence[question.id] ?? 55}
                        review={reviews[question.id]}
                        isSubmitting={!!busyActions[`evaluate:${question.id}` as BusyActionKey]}
                        showExpectedAnswer={revealedAnswers[question.id] ?? false}
                        onAnswerChange={(value) =>
                          setAnswers((current) => ({ ...current, [question.id]: value }))
                        }
                        onConfidenceChange={(next) =>
                          setConfidence((current) => ({ ...current, [question.id]: next }))
                        }
                        onToggleExpectedAnswer={() =>
                          setRevealedAnswers((current) => ({
                            ...current,
                            [question.id]: !(current[question.id] ?? false),
                          }))
                        }
                        onSubmit={() => void evaluateQuestion(question)}
                      />
                    ))}
                    {mock?.length === "full" && mock.questions.length > 12 ? (
                      <div className="rounded-[24px] border border-dashed border-stone-900/20 bg-stone-50/70 p-5 text-sm leading-7 text-stone-600">
                        Full mock mode generated {mock.questions.length} items. The interface shows the first 12 for usability, and the rest remain in the response payload for expansion in a later pass.
                      </div>
                    ) : null}
                  </div>
                ) : isDrillLoading || isMockLoading ? (
                  <div className="space-y-4">
                    <LoadingPanel
                      eyebrow={isMockLoading ? "Mock generation" : "Drill generation"}
                      title={isMockLoading ? "Building a timed exam set" : "Building a pressure drill"}
                      body={isMockLoading
                        ? "The tutor is assembling exam-style questions with stronger distractor logic, timing pressure, and dual SSCP/CISSP review hooks."
                        : "The tutor is selecting meaningful questions, scenario context, and answer guidance so the next drill feels like real certification pressure."}
                    />
                    <div className="grid gap-4 xl:grid-cols-2">
                      <LoadingPanel
                        eyebrow="Chronometer"
                        title="Preparing the timer"
                        body="Your timed session shell is ready so the countdown context appears as soon as the first items land."
                      />
                      <LoadingPanel
                        eyebrow="Dual review"
                        title="Preloading answer evaluation"
                        body="Expected answers, rationale, and SSCP/CISSP review channels are being queued for instant feedback."
                      />
                    </div>
                  </div>
                ) : (
                  <div className="rounded-[24px] border border-dashed border-stone-900/20 bg-stone-50/70 p-6 text-sm leading-7 text-stone-600">
                    Generate a drill or mock to start answering questions.
                  </div>
                )}
              </SectionShell>
            ) : null}

            {workspace === "resources" ? (
              <SectionShell
                title="Validated study paths"
                subtitle="Use trusted study guides and your local SSCP/CISSP PDFs together. Each card explains why it matters and helps you turn it into SSCP/CISSP reasoning."
                actions={
                  <button
                    type="button"
                    disabled={isResourcesLoading}
                    onClick={() => void loadResources(selectedDomain)}
                    className={clsx(
                      "rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800",
                      isResourcesLoading && "cursor-not-allowed opacity-60",
                    )}
                  >
                    {isResourcesLoading ? "Refreshing resources..." : "Refresh resources"}
                  </button>
                }
              >
                <div className="grid gap-4 xl:grid-cols-[minmax(0,0.82fr)_minmax(0,1.18fr)]">
                  <div className="rounded-[24px] border border-stone-900/10 bg-stone-50/80 p-5">
                    <label className="block text-xs uppercase tracking-[0.22em] text-stone-500">
                      Topic filter
                    </label>
                    <input
                      type="text"
                      value={topicHint}
                      onChange={(event) => setTopicHint(event.target.value)}
                      className="mt-3 w-full rounded-[18px] border border-stone-900/10 bg-white px-4 py-3 text-sm font-medium text-stone-900 outline-none transition focus:border-stone-900/30"
                    />
                    <p className="mt-4 text-sm leading-7 text-stone-600">{resources.summary}</p>
                    <div className="mt-4">
                      <SscpReaderControls text={resources.summary} label="resource summary" />
                    </div>
                  </div>
                  <div className="grid gap-4">
                    {isResourcesLoading && filteredResources.length === 0 ? (
                      <>
                        <LoadingPanel
                          eyebrow="Trusted and PDF sources"
                          title="Finding relevant study paths"
                          body="The tutor is selecting the most useful trusted references and SSCP/CISSP PDF excerpts for this domain and topic."
                        />
                        <LoadingPanel
                          eyebrow="Strategic value"
                          title="Scoring long-term relevance"
                          body="Each resource is being tagged for SSCP fit, CISSP bridge value, and future leadership utility."
                        />
                      </>
                    ) : (
                      filteredResources.map((resource) => (
                        <ResourceCard
                          key={resource.id}
                          resource={resource}
                          onSave={saveResource}
                        />
                      ))
                    )}
                  </div>
                </div>
              </SectionShell>
            ) : null}

            {workspace === "library" ? (
              <SectionShell
                title="Library and extension companion"
                subtitle="Review imported PDF chunks, saved study paths, and extension captures. This is where your book corpus and your active study meet."
                actions={
                  <>
                    <button
                      type="button"
                      disabled={isNotesImporting}
                      onClick={() => void importNotes(true)}
                      className={clsx(
                        "rounded-full border border-stone-900/10 bg-stone-100 px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-200",
                        isNotesImporting && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isNotesImporting ? "Re-importing PDFs..." : "Re-import PDFs"}
                    </button>
                    <button
                      type="button"
                      disabled={isCapturesLoading}
                      onClick={() => void loadCaptures()}
                      className={clsx(
                        "rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800",
                        isCapturesLoading && "cursor-not-allowed opacity-60",
                      )}
                    >
                      {isCapturesLoading ? "Refreshing captures..." : "Refresh captures"}
                    </button>
                  </>
                }
              >
                <div className="grid gap-5 xl:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)]">
                  <div className="space-y-5">
                    <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Imported PDF corpus</div>
                      <p className="mt-2 text-sm leading-7 text-stone-600">
                        {notes.length
                          ? `You have ${notes.length} PDF chunks available from the local SSCP/CISSP study books.`
                          : "Import the local study PDF folder to populate this section."}
                      </p>
                      {notes.length ? (
                        <div className="mt-4 space-y-4">
                          <StudyMindmap
                            title="PDF reinforcement map"
                            branches={SSCP_DOMAINS.slice(0, 4).map((domain) => ({
                              title: domain.title,
                              items: notes.filter((note) => note.domainId === domain.id).length
                                ? notes
                                    .filter((note) => note.domainId === domain.id)
                                    .slice(0, 2)
                                    .map((note) => note.title)
                                : ["No imported notes yet"],
                            }))}
                          />
                          <StudyFlowDiagram
                            title="How the PDF corpus should be used"
                            steps={[
                              "Read the lesson summary and control objective.",
                              "Use the PDF chunk to reinforce vocabulary and examples.",
                              "Practice the concept in a drill.",
                              "Let the dual review correct weak or shallow answers.",
                            ]}
                          />
                        </div>
                      ) : null}
                      <div className="mt-4 space-y-3">
                        {notes.slice(0, 8).map((note) => (
                          <div key={note.id} className="rounded-[18px] bg-stone-50 px-4 py-3">
                            <div className="flex flex-wrap items-center gap-2">
                              <SourceBadge trustLevel="user_notes" label="PDF library" />
                              <span className="text-xs text-stone-500">{note.fileName}</span>
                            </div>
                            <h4 className="mt-2 text-sm font-semibold text-stone-900">{note.title}</h4>
                            <p className="mt-2 text-sm leading-6 text-stone-600">{note.excerpt}</p>
                            <div className="mt-3">
                              <SscpReaderControls text={note.excerpt} label="note" />
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                    <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Saved resources</div>
                      <div className="mt-4 space-y-3">
                        {savedResources.length ? (
                          savedResources.map((resource) => (
                            <div key={resource.id} className="rounded-[18px] bg-stone-50 px-4 py-3">
                              <div className="flex flex-wrap items-center gap-2">
                                <SourceBadge
                                  trustLevel={resource.sourceType}
                                  label={resource.sourceType === "trusted_live" ? "Trusted live" : resource.sourceType === "official" ? "Official" : "PDF library"}
                                />
                                <span className="text-xs text-stone-500">{resource.sourceName}</span>
                              </div>
                              <h4 className="mt-2 text-sm font-semibold text-stone-900">
                                {resource.title}
                              </h4>
                              <p className="mt-2 text-sm leading-6 text-stone-600">
                                {resource.summary}
                              </p>
                            </div>
                          ))
                        ) : (
                          <div className="rounded-[18px] bg-stone-50 px-4 py-3 text-sm text-stone-600">
                            Save PDF study paths from the Resources tab to build your own SSCP-to-CISSP reading path.
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="space-y-5">
                    <div id="extension-companion" className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                        Browser extension companion
                      </div>
                      <h3 className="mt-3 text-lg font-semibold text-stone-900">
                        Phase 2 is included
                      </h3>
                      <p className="mt-3 text-sm leading-7 text-stone-600">
                        Load the unpacked extension from <code className="rounded bg-stone-100 px-1.5 py-0.5">browser-extension/sscp-companion</code>.
                        It can capture the current page or your selection, then push it back into this tutor as a study reference.
                      </p>
                      <div className="mt-4 text-sm leading-7 text-stone-600">
                        Open Chrome or Edge extensions, enable Developer Mode, click <strong>Load unpacked</strong>, and choose the extension folder.
                      </div>
                    </div>
                    <div className="rounded-[24px] border border-stone-900/10 bg-white/80 p-5">
                      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Incoming captures</div>
                      <div className="mt-4 space-y-3">
                        {captures.length ? (
                          captures.map((capture) => (
                            <div key={capture.id} className="rounded-[18px] bg-stone-50 px-4 py-3">
                              <h4 className="text-sm font-semibold text-stone-900">{capture.title}</h4>
                              <a
                                href={capture.url}
                                target="_blank"
                                rel="noreferrer"
                                className="mt-1 block text-xs text-sky-700 underline-offset-4 hover:underline"
                              >
                                {capture.url}
                              </a>
                              <p className="mt-2 text-sm leading-6 text-stone-600">
                                {capture.selectionText || capture.pageText?.slice(0, 420) || "No captured text yet."}
                              </p>
                              <div className="mt-3 flex flex-wrap gap-2">
                                <button
                                  type="button"
                                  onClick={() => openCaptureStudyAid(capture)}
                                  className="rounded-full border border-stone-900 bg-stone-900 px-3 py-1.5 text-xs font-semibold text-stone-50 transition hover:bg-stone-800"
                                >
                                  Create study aid
                                </button>
                                <button
                                  type="button"
                                  onClick={() => {
                                    openCaptureStudyAid(capture);
                                    void generateDrill("scenario");
                                  }}
                                  className="rounded-full border border-stone-900/10 bg-white px-3 py-1.5 text-xs font-semibold text-stone-700 transition hover:bg-stone-100"
                                >
                                  Quiz from this capture
                                </button>
                              </div>
                            </div>
                          ))
                        ) : (
                          <div className="rounded-[18px] bg-stone-50 px-4 py-3 text-sm text-stone-600">
                            No extension captures yet. Use the extension to send a page or selected text into the tutor.
                          </div>
                        )}
                      </div>
                    </div>
                    {captureAid ? (
                      <CaptureStudyAidCard
                        aid={captureAid.aid}
                        title={captures.find((capture) => capture.id === captureAid.captureId)?.title ?? "Capture study aid"}
                        onLaunchScenario={() => void generateDrill("scenario")}
                      />
                    ) : null}
                    <ActionHealthPanel actions={ACTION_HEALTH_MATRIX} />
                  </div>
                </div>
              </SectionShell>
            ) : null}
          </section>
        </div>
      </div>
    </main>
  );
}
