"use client";

import React, { useMemo, useState } from "react";

import SscpReaderControls from "@/app/components/SscpReaderControls";
import { ActionHealthCheck, CaptureStudyAid, Flashcard, LessonCheckpoint, LessonScenario, StrategicLens, WorkedExample } from "@/lib/sscp/types";

function shellClass() {
  return "rounded-[24px] border border-stone-900/10 bg-white/85 p-5";
}

export function FlashcardDeck({
  cards,
  title = "Flashcard deck",
}: {
  cards: Flashcard[];
  title?: string;
}) {
  const [index, setIndex] = useState(0);
  const [revealed, setRevealed] = useState(false);
  const card = cards[index];

  if (!card) {
    return (
      <div className={shellClass()}>
        <div className="text-sm text-stone-600">No flashcards available yet.</div>
      </div>
    );
  }

  return (
    <div className={shellClass()}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">{title}</div>
          <div className="mt-2 text-lg font-semibold text-stone-900">
            Card {index + 1} of {cards.length}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => {
              setIndex((current) => (current === 0 ? cards.length - 1 : current - 1));
              setRevealed(false);
            }}
            className="rounded-full border border-stone-900/10 bg-stone-100 px-3 py-1.5 text-xs font-semibold text-stone-700 transition hover:bg-stone-200"
          >
            Previous
          </button>
          <button
            type="button"
            onClick={() => {
              setIndex((current) => (current === cards.length - 1 ? 0 : current + 1));
              setRevealed(false);
            }}
            className="rounded-full border border-stone-900/10 bg-stone-100 px-3 py-1.5 text-xs font-semibold text-stone-700 transition hover:bg-stone-200"
          >
            Next
          </button>
        </div>
      </div>
      <div className="mt-5 rounded-[24px] border border-stone-900/10 bg-[linear-gradient(180deg,rgba(249,246,241,0.95),rgba(255,255,255,0.96))] p-6">
        <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Front</div>
        <p className="mt-3 text-base leading-8 text-stone-900">{card.front}</p>
        {card.hint ? (
          <div className="mt-4 rounded-[18px] bg-amber-50 px-4 py-3 text-sm text-amber-950">
            <span className="font-semibold">Hint:</span> {card.hint}
          </div>
        ) : null}
        <div className="mt-5 flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setRevealed((current) => !current)}
            className="rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800"
          >
            {revealed ? "Hide answer" : "Reveal answer"}
          </button>
        </div>
        {revealed ? (
          <div className="mt-5 rounded-[22px] border border-emerald-700/20 bg-emerald-50/70 p-5">
            <div className="text-xs uppercase tracking-[0.22em] text-emerald-800">Back</div>
            <p className="mt-3 text-sm leading-7 text-emerald-950">{card.back}</p>
            {card.cue ? (
              <div className="mt-4 rounded-[18px] bg-white px-4 py-3 text-sm text-emerald-950">
                <span className="font-semibold">Memory cue:</span> {card.cue}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
      <div className="mt-4">
        <SscpReaderControls text={`${card.front} ${revealed ? card.back : card.hint ?? ""}`} label="flashcard" />
      </div>
    </div>
  );
}

export function WorkedExampleStudio({
  examples,
}: {
  examples: WorkedExample[];
}) {
  const [activeId, setActiveId] = useState(examples[0]?.id ?? "");
  const active = useMemo(
    () => examples.find((example) => example.id === activeId) ?? examples[0],
    [activeId, examples],
  );

  if (!active) return null;

  return (
    <div className={shellClass()}>
      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Worked examples</div>
      <div className="mt-4 flex flex-wrap gap-2">
        {examples.map((example) => (
          <button
            key={example.id}
            type="button"
            onClick={() => setActiveId(example.id)}
            className={`rounded-full border px-3 py-1.5 text-xs font-semibold transition ${
              example.id === active.id
                ? "border-stone-900 bg-stone-900 text-stone-50"
                : "border-stone-900/10 bg-stone-100 text-stone-700 hover:bg-stone-200"
            }`}
          >
            {example.title}
          </button>
        ))}
      </div>
      <div className="mt-5 grid gap-4 xl:grid-cols-2">
        <div className="rounded-[22px] bg-stone-50 px-5 py-4">
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Situation</div>
          <p className="mt-3 text-sm leading-7 text-stone-700">{active.situation}</p>
          <div className="mt-4 rounded-[18px] bg-white px-4 py-3 text-sm text-stone-700">
            <span className="font-semibold text-stone-900">SSCP move:</span> {active.sscpMove}
          </div>
        </div>
        <div className="rounded-[22px] bg-stone-50 px-5 py-4">
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Why it works</div>
          <p className="mt-3 text-sm leading-7 text-stone-700">{active.whyItWorks}</p>
          <div className="mt-4 rounded-[18px] bg-amber-50 px-4 py-3 text-sm text-amber-950">
            <span className="font-semibold">CISSP bridge:</span> {active.cisspBridge}
          </div>
          <ul className="mt-4 space-y-2 text-sm text-stone-600">
            {active.pitfalls.map((pitfall) => (
              <li key={pitfall}>• {pitfall}</li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}

export function ScenarioStudio({
  scenarios,
  onLaunchDrill,
}: {
  scenarios: LessonScenario[];
  onLaunchDrill: () => void;
}) {
  const [activeId, setActiveId] = useState(scenarios[0]?.id ?? "");
  const active = useMemo(
    () => scenarios.find((scenario) => scenario.id === activeId) ?? scenarios[0],
    [activeId, scenarios],
  );

  if (!active) return null;

  return (
    <div className={shellClass()}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Scenario studio</div>
          <h4 className="mt-2 text-lg font-semibold text-stone-900">{active.title}</h4>
        </div>
        <button
          type="button"
          onClick={onLaunchDrill}
          className="rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800"
        >
          Launch scenario drill
        </button>
      </div>
      <div className="mt-4 flex flex-wrap gap-2">
        {scenarios.map((scenario) => (
          <button
            key={scenario.id}
            type="button"
            onClick={() => setActiveId(scenario.id)}
            className={`rounded-full border px-3 py-1.5 text-xs font-semibold transition ${
              scenario.id === active.id
                ? "border-stone-900 bg-stone-900 text-stone-50"
                : "border-stone-900/10 bg-stone-100 text-stone-700 hover:bg-stone-200"
            }`}
          >
            {scenario.title}
          </button>
        ))}
      </div>
      <div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)]">
        <div className="rounded-[22px] bg-stone-50 px-5 py-4">
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Situation</div>
          <p className="mt-3 text-sm leading-7 text-stone-700">{active.situation}</p>
          <div className="mt-4 flex flex-wrap gap-2">
            {active.signals.map((signal) => (
              <span
                key={signal}
                className="rounded-full border border-stone-900/10 bg-white px-3 py-1 text-xs font-semibold text-stone-700"
              >
                {signal}
              </span>
            ))}
          </div>
        </div>
        <div className="space-y-3">
          <div className="rounded-[22px] bg-white px-5 py-4 shadow-[0_10px_30px_rgba(63,46,32,0.05)]">
            <div className="text-xs uppercase tracking-[0.22em] text-stone-500">SSCP response</div>
            <p className="mt-3 text-sm leading-7 text-stone-700">{active.sscpResponse}</p>
          </div>
          <div className="rounded-[22px] bg-amber-50 px-5 py-4">
            <div className="text-xs uppercase tracking-[0.22em] text-amber-800">CISSP response</div>
            <p className="mt-3 text-sm leading-7 text-amber-950">{active.cisspResponse}</p>
          </div>
          <div className="rounded-[22px] bg-stone-900 px-5 py-4 text-stone-50">
            <div className="text-xs uppercase tracking-[0.22em] text-stone-300">CTO horizon</div>
            <p className="mt-3 text-sm leading-7 text-stone-100">{active.ctoHorizon}</p>
          </div>
        </div>
      </div>
      <div className="mt-4">
        <SscpReaderControls
          text={`${active.situation} SSCP response. ${active.sscpResponse} CISSP response. ${active.cisspResponse}`}
          label="scenario"
        />
      </div>
    </div>
  );
}

function checkpointIsCorrect(
  checkpoint: LessonCheckpoint,
  answer: string | string[] | undefined,
): boolean {
  if (!checkpoint.correctOptionIds?.length) return false;
  const selected = new Set(Array.isArray(answer) ? answer : answer ? [answer] : []);
  const correct = new Set(checkpoint.correctOptionIds);
  if (selected.size !== correct.size) return false;
  return [...correct].every((id) => selected.has(id));
}

function checkpointPartialHits(
  checkpoint: LessonCheckpoint,
  answer: string | string[] | undefined,
): number {
  if (!checkpoint.correctOptionIds?.length) return 0;
  const selected = Array.isArray(answer) ? answer : answer ? [answer] : [];
  return selected.filter((id) => checkpoint.correctOptionIds!.includes(id)).length;
}

function formatCheckpointLabel(format: LessonCheckpoint["format"]) {
  if (format === "single_select") return "Single select";
  if (format === "multi_select") return "Multi select";
  return "Short answer";
}

export function CheckpointLab({
  checkpoints,
  onMiss,
}: {
  checkpoints: LessonCheckpoint[];
  onMiss: (message: string) => void;
}) {
  const [answers, setAnswers] = useState<Record<string, string | string[]>>({});
  const [revealed, setRevealed] = useState<Record<string, boolean>>({});

  if (!checkpoints.length) return null;

  return (
    <div className={shellClass()}>
      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Checkpoint lab</div>
      <div className="mt-4 space-y-4">
        {checkpoints.map((checkpoint) => {
          const answer = answers[checkpoint.id];
          const answerText = Array.isArray(answer) ? answer.join(", ") : answer ?? "";
          const isCorrect = checkpointIsCorrect(checkpoint, answer);
          const partialHits = checkpointPartialHits(checkpoint, answer);
          const isMulti = checkpoint.format === "multi_select";
          const totalCorrect = checkpoint.correctOptionIds?.length ?? 0;

          return (
            <div key={checkpoint.id} className="rounded-[22px] border border-stone-900/10 bg-stone-50/80 p-5">
              <div className="flex flex-wrap items-center gap-2">
                <div className="text-xs uppercase tracking-[0.22em] text-stone-500">
                  {formatCheckpointLabel(checkpoint.format)}
                </div>
                {isMulti ? (
                  <div className="rounded-full border border-amber-700/20 bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-900">
                    Select {totalCorrect} correct
                  </div>
                ) : null}
              </div>
              <p className="mt-3 text-sm leading-7 text-stone-800">{checkpoint.prompt}</p>

              {checkpoint.format === "single_select" ? (
                <div className="mt-4 space-y-2">
                  {checkpoint.options?.map((option) => (
                    <label
                      key={option.id}
                      className="flex items-start gap-3 rounded-[18px] border border-stone-900/10 bg-white px-4 py-3 text-sm text-stone-700"
                    >
                      <input
                        type="radio"
                        checked={answerText === option.id}
                        onChange={() =>
                          setAnswers((current) => ({ ...current, [checkpoint.id]: option.id }))
                        }
                      />
                      <span>
                        <span className="font-semibold text-stone-900">{option.label}.</span> {option.text}
                      </span>
                    </label>
                  ))}
                </div>
              ) : checkpoint.format === "multi_select" ? (
                <div className="mt-4 space-y-2">
                  {checkpoint.options?.map((option) => {
                    const selections = Array.isArray(answer) ? answer : [];
                    const checked = selections.includes(option.id);
                    const isRevealedCorrect = revealed[checkpoint.id] && checkpoint.correctOptionIds?.includes(option.id);
                    const isRevealedWrong = revealed[checkpoint.id] && checked && !checkpoint.correctOptionIds?.includes(option.id);
                    return (
                      <label
                        key={option.id}
                        className={`flex items-start gap-3 rounded-[18px] border px-4 py-3 text-sm text-stone-700 transition ${
                          isRevealedCorrect
                            ? "border-emerald-700/25 bg-emerald-50"
                            : isRevealedWrong
                              ? "border-rose-700/20 bg-rose-50"
                              : "border-stone-900/10 bg-white"
                        }`}
                      >
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={() => {
                            const next = new Set(selections);
                            if (checked) next.delete(option.id);
                            else next.add(option.id);
                            setAnswers((current) => ({ ...current, [checkpoint.id]: [...next] }));
                          }}
                        />
                        <span>
                          <span className="font-semibold text-stone-900">{option.label}.</span> {option.text}
                          {isRevealedCorrect ? (
                            <span className="ml-2 rounded-full border border-emerald-700/20 bg-white px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.14em] text-emerald-900">
                              Correct
                            </span>
                          ) : null}
                        </span>
                      </label>
                    );
                  })}
                </div>
              ) : (
                <textarea
                  value={answerText}
                  onChange={(event) =>
                    setAnswers((current) => ({ ...current, [checkpoint.id]: event.target.value }))
                  }
                  className="mt-4 min-h-[120px] w-full rounded-[18px] border border-stone-900/10 bg-white px-4 py-3 text-sm leading-7 text-stone-900 outline-none transition focus:border-stone-900/25"
                  placeholder="Write your checkpoint answer here."
                />
              )}

              <div className="mt-4 flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => {
                    const nextReveal = !revealed[checkpoint.id];
                    setRevealed((current) => ({ ...current, [checkpoint.id]: nextReveal }));
                    if (nextReveal && checkpoint.correctOptionIds?.length && !isCorrect) {
                      onMiss(checkpoint.remediation);
                    }
                  }}
                  className="rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800"
                >
                  {revealed[checkpoint.id] ? "Hide coaching" : "Check answer"}
                </button>
                <div className="rounded-full border border-stone-900/10 bg-white px-3 py-2 text-xs font-semibold text-stone-600">
                  Objective {checkpoint.objectiveId}
                </div>
              </div>

              {revealed[checkpoint.id] ? (
                <div className="mt-4 rounded-[20px] border border-emerald-700/20 bg-emerald-50/70 p-4">
                  <div className="text-xs uppercase tracking-[0.22em] text-emerald-800">Coaching</div>
                  <p className="mt-2 text-sm leading-7 text-emerald-950">{checkpoint.expectedAnswer}</p>
                  <div className="mt-3 rounded-[16px] bg-white px-4 py-3 text-sm text-emerald-950">
                    <span className="font-semibold">Tip:</span> {checkpoint.coachingTip}
                  </div>
                  {!checkpoint.correctOptionIds?.length ? (
                    <div className="mt-3 rounded-[16px] bg-amber-50 px-4 py-3 text-sm text-amber-950">
                      <span className="font-semibold">Self-check:</span> Compare your answer to the model and tighten it before moving on.
                    </div>
                  ) : isCorrect ? null : isMulti && partialHits > 0 ? (
                    <div className="mt-3 rounded-[16px] bg-amber-50 px-4 py-3 text-sm text-amber-950">
                      <span className="font-semibold">Partial:</span> You identified {partialHits} of {totalCorrect} correct options. Review the highlighted answers and try again.
                    </div>
                  ) : (
                    <div className="mt-3 rounded-[16px] bg-rose-50 px-4 py-3 text-sm text-rose-900">
                      <span className="font-semibold">Redirect:</span> {checkpoint.remediation}
                    </div>
                  )}
                </div>
              ) : null}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function StrategicLensCard({
  lens,
}: {
  lens: StrategicLens;
}) {
  return (
    <div className="rounded-[24px] border border-stone-900/10 bg-stone-900 p-5 text-stone-50">
      <div className="text-xs uppercase tracking-[0.22em] text-stone-300">Strategic lens</div>
      <h4 className="mt-2 text-lg font-semibold">{lens.title}</h4>
      <div className="mt-4 grid gap-3">
        <div className="rounded-[18px] bg-white/10 px-4 py-3">
          <div className="text-xs uppercase tracking-[0.22em] text-stone-300">Business impact</div>
          <p className="mt-2 text-sm leading-7 text-stone-100">{lens.businessImpact}</p>
        </div>
        <div className="rounded-[18px] bg-white/10 px-4 py-3">
          <div className="text-xs uppercase tracking-[0.22em] text-stone-300">Architecture tradeoff</div>
          <p className="mt-2 text-sm leading-7 text-stone-100">{lens.architectureTradeoff}</p>
        </div>
        <div className="rounded-[18px] bg-amber-400/20 px-4 py-3">
          <div className="text-xs uppercase tracking-[0.22em] text-amber-100">Leadership prompt</div>
          <p className="mt-2 text-sm leading-7 text-amber-50">{lens.leadershipPrompt}</p>
        </div>
      </div>
    </div>
  );
}

export function CaptureStudyAidCard({
  aid,
  title,
  onLaunchScenario,
}: {
  aid: CaptureStudyAid;
  title: string;
  onLaunchScenario: () => void;
}) {
  return (
    <div className={shellClass()}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Capture study aid</div>
          <h4 className="mt-2 text-lg font-semibold text-stone-900">{title}</h4>
        </div>
        <button
          type="button"
          onClick={onLaunchScenario}
          className="rounded-full border border-stone-900 bg-stone-900 px-4 py-2 text-sm font-semibold text-stone-50 transition hover:bg-stone-800"
        >
          Launch scenario drill
        </button>
      </div>
      <p className="mt-4 text-sm leading-7 text-stone-700">{aid.summary}</p>
      <div className="mt-4 rounded-[18px] bg-amber-50 px-4 py-3 text-sm text-amber-950">
        <span className="font-semibold">Strategic prompt:</span> {aid.strategicPrompt}
      </div>
      <div className="mt-4 rounded-[18px] bg-stone-50 px-4 py-3 text-sm text-stone-700">
        <span className="font-semibold text-stone-900">Scenario prompt:</span> {aid.scenarioPrompt}
      </div>
      <div className="mt-4">
        <FlashcardDeck cards={aid.flashcards} title="Capture flashcards" />
      </div>
    </div>
  );
}

export function ActionHealthPanel({
  actions,
}: {
  actions: ActionHealthCheck[];
}) {
  return (
    <div className={shellClass()}>
      <div className="text-xs uppercase tracking-[0.22em] text-stone-500">Reliability matrix</div>
      <p className="mt-2 text-sm leading-6 text-stone-600">
        These are the interactive actions the tutor now treats as first-class and testable.
      </p>
      <div className="mt-4 grid gap-3">
        {actions.map((action) => (
          <div key={action.id} className="rounded-[18px] border border-stone-900/10 bg-stone-50 px-4 py-3">
            <div className="flex flex-wrap items-center gap-2">
              <span className="rounded-full border border-stone-900/10 bg-white px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-stone-500">
                {action.workspace}
              </span>
              <span className="text-sm font-semibold text-stone-900">{action.label}</span>
            </div>
            <p className="mt-2 text-sm leading-6 text-stone-600">{action.expectedOutcome}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
