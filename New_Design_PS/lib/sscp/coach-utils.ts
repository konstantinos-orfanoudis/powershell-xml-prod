import { ExtensionCapture, ActionHealthCheck, CaptureStudyAid, Flashcard } from "@/lib/sscp/types";

function cleanSentences(text: string): string[] {
  return text
    .replace(/\s+/g, " ")
    .split(/(?<=[.!?])\s+/)
    .map((part) => part.trim())
    .filter((part) => part.length > 30);
}

function extractKeywords(text: string): string[] {
  const stopWords = new Set([
    "about",
    "after",
    "again",
    "against",
    "being",
    "because",
    "between",
    "could",
    "doing",
    "first",
    "found",
    "their",
    "there",
    "these",
    "those",
    "under",
    "which",
    "while",
    "would",
  ]);

  const seen = new Set<string>();
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length >= 6 && !stopWords.has(token))
    .filter((token) => {
      if (seen.has(token)) return false;
      seen.add(token);
      return true;
    })
    .slice(0, 5);
}

function createCaptureFlashcards(title: string, sentences: string[], keywords: string[]): Flashcard[] {
  const sentenceCards = sentences.slice(0, 2).map((sentence, index) => ({
    id: `capture-sentence-${index + 1}`,
    front: `What is the core security point from "${title}" item ${index + 1}?`,
    back: sentence,
    hint: "Restate this in your own operational language before revealing the answer.",
    cue: "Explain the control principle and the risk it changes.",
  }));

  const keywordCards = keywords.slice(0, 3).map((keyword, index) => ({
    id: `capture-keyword-${index + 1}`,
    front: `Why would ${keyword} matter in an SSCP or CISSP discussion?`,
    back: `Tie ${keyword} to one operational control, one risk consequence, and one leadership concern from the captured page.`,
    hint: "Think in SSCP first, then zoom out into governance or architecture.",
    cue: "Operator move -> enterprise consequence",
  }));

  return [...sentenceCards, ...keywordCards];
}

export function buildCaptureStudyAid(capture: ExtensionCapture): CaptureStudyAid {
  const rawText = capture.selectionText || capture.pageText || "";
  const sentences = cleanSentences(rawText);
  const keywords = extractKeywords(rawText);
  const summary =
    sentences.slice(0, 2).join(" ") ||
    "Use this captured page as a practical example, then explain what control, risk, and business implication it illustrates.";

  return {
    summary,
    flashcards: createCaptureFlashcards(capture.title, sentences, keywords),
    scenarioPrompt: `You captured material about "${capture.title}". Explain how the same ideas would influence an SSCP response in the short term and a CISSP or CTO-level decision over the long term.`,
    strategicPrompt:
      "If this situation affected a real business unit, what should be fixed immediately, what should be changed structurally, and what should be escalated to leadership?",
  };
}

export const ACTION_HEALTH_MATRIX: ActionHealthCheck[] = [
  {
    id: "global-import-notes",
    workspace: "global",
    label: "Import study PDFs",
    expectedOutcome: "Imports the local PDF study corpus and moves the learner into the library view with updated chunk counts.",
  },
  {
    id: "global-open-extension-anchor",
    workspace: "global",
    label: "Browser extension anchor",
    expectedOutcome: "Moves focus to the extension companion guidance so setup never dead-ends.",
  },
  {
    id: "plan-generate-sprint",
    workspace: "plan",
    label: "Generate sprint",
    expectedOutcome: "Builds a fresh weekly sprint with readiness, pressure note, and study tasks.",
  },
  {
    id: "learn-build-lesson",
    workspace: "learn",
    label: "Build lesson",
    expectedOutcome: "Generates a lesson that keeps official framing primary, adds trusted references, and uses PDF excerpts as reinforcement.",
  },
  {
    id: "drill-mixed",
    workspace: "drill",
    label: "Mixed drill",
    expectedOutcome: "Generates a mixed-format drill and starts the chronometer.",
  },
  {
    id: "drill-scenario",
    workspace: "drill",
    label: "Scenario drill",
    expectedOutcome: "Generates a scenario-heavy drill with bridge-level reasoning prompts.",
  },
  {
    id: "drill-mini-mock",
    workspace: "drill",
    label: "Mini mock",
    expectedOutcome: "Generates a timed mini mock with clear guidance and review hooks.",
  },
  {
    id: "drill-evaluate-answer",
    workspace: "drill",
    label: "Evaluate answer",
    expectedOutcome: "Returns dual SSCP/CISSP feedback and updates mastery.",
  },
  {
    id: "resources-refresh",
    workspace: "resources",
    label: "Refresh resources",
    expectedOutcome: "Reloads trusted study paths together with related PDF chapter excerpts for the active topic.",
  },
  {
    id: "resources-save-resource",
    workspace: "resources",
    label: "Save to library",
    expectedOutcome: "Stores a resource locally so it remains part of the learner's longer-term path.",
  },
  {
    id: "library-reimport-notes",
    workspace: "library",
    label: "Re-import PDFs",
    expectedOutcome: "Refreshes cached PDF chunks from the local study corpus.",
  },
  {
    id: "library-refresh-captures",
    workspace: "library",
    label: "Refresh captures",
    expectedOutcome: "Reloads incoming browser-extension captures into the tutor.",
  },
  {
    id: "library-capture-study-aid",
    workspace: "library",
    label: "Create capture study aid",
    expectedOutcome: "Transforms captured text into flashcards, a scenario prompt, and a strategic reflection prompt.",
  },
  {
    id: "extension-capture-page",
    workspace: "extension",
    label: "Capture page",
    expectedOutcome: "Stores the active page in the tutor library as a study reference.",
  },
  {
    id: "extension-capture-selection",
    workspace: "extension",
    label: "Capture selection",
    expectedOutcome: "Stores the selected text in the tutor library for focused review.",
  },
  {
    id: "extension-quiz-page",
    workspace: "extension",
    label: "Quiz this page",
    expectedOutcome: "Captures the page and opens the tutor ready to convert it into study material.",
  },
  {
    id: "extension-read-selection",
    workspace: "extension",
    label: "Read selection",
    expectedOutcome: "Speaks the selected or visible page text aloud through the browser TTS engine.",
  },
];
