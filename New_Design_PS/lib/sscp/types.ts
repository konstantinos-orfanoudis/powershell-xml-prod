export type SourceTrustLevel = "official" | "trusted_live" | "user_notes";

export type SscpDomainId =
  | "security-concepts-practices"
  | "access-controls"
  | "risk-identification-monitoring-analysis"
  | "incident-response-recovery"
  | "cryptography"
  | "network-communications-security"
  | "systems-application-security";

export type CisspDomainId =
  | "security-risk-management"
  | "asset-security"
  | "security-architecture-engineering"
  | "communication-network-security"
  | "identity-access-management"
  | "security-assessment-testing"
  | "security-operations"
  | "software-development-security";

export type QuestionFormat =
  | "single_select"
  | "multi_select"
  | "short_answer"
  | "scenario";

export type ThinkingLevel = "sscp" | "cissp" | "cto";

export type DomainStudyMode = "combined" | "single";

export interface SourceCitation {
  id: string;
  label: string;
  url?: string;
  trustLevel: SourceTrustLevel;
  sourceName: string;
  accessedAt?: string;
  publishedAt?: string;
  note?: string;
}

export interface SscpObjective {
  id: string;
  domainId: SscpDomainId;
  title: string;
  summary: string;
  keywords: string[];
  cisspBridgeTopics: string[];
}

export interface SscpDomain {
  id: SscpDomainId;
  title: string;
  weight: number;
  summary: string;
  officialCitation: SourceCitation;
  glossary: string[];
  objectives: SscpObjective[];
}

export interface CisspDomain {
  id: CisspDomainId;
  title: string;
  weight: number;
  summary: string;
  officialCitation: SourceCitation;
}

export interface LearnerProfile {
  learnerName?: string;
  weeklyHours: number;
  currentRole: string;
  targetMode: "mastery" | "deadline";
  examDate?: string;
  strengths: SscpDomainId[];
  weakAreas: SscpDomainId[];
  currentConfidence: number;
}

export interface DomainMastery {
  domainId: SscpDomainId;
  score: number;
  confidence: number;
  lastReviewedAt?: string;
  attempts: number;
}

export interface MasterySnapshot {
  overallReadiness: number;
  cisspBridgeReadiness: number;
  confidenceCalibration: number;
  recentMocks: number[];
  domains: DomainMastery[];
}

export interface StudyTask {
  id: string;
  title: string;
  phase: "foundation" | "pressure" | "bridge";
  intensity: "steady" | "stretch" | "pressure";
  domainIds: SscpDomainId[];
  durationMinutes: number;
  description: string;
}

export interface StudySprintPlan {
  generatedAt: string;
  readiness: MasterySnapshot;
  summary: string;
  pressureNote: string;
  tasks: StudyTask[];
}

export interface ImportedNoteChunk {
  id: string;
  domainId: SscpDomainId;
  title: string;
  fileName: string;
  excerpt: string;
  sectionLabel: string;
  keywords: string[];
  sourceType: "user_notes";
}

export interface LearningResource {
  id: string;
  title: string;
  url: string;
  format: "article" | "video" | "guide" | "course";
  sourceName: string;
  sourceType: SourceTrustLevel;
  publishedAt?: string;
  domainIds: SscpDomainId[];
  difficulty: "foundation" | "intermediate" | "advanced";
  timeToConsume: string;
  sscpFit: string;
  cisspBridgeValue: string;
  summary: string;
  whyItMatters: string;
  strategicValue?: string;
  readableText?: string;
  citations: SourceCitation[];
}

export interface QuestionOption {
  id: string;
  label: string;
  text: string;
}

export interface OptionRationale {
  optionId: string;
  rationale: string;
}

export interface Flashcard {
  id: string;
  front: string;
  back: string;
  hint?: string;
  cue?: string;
}

export interface WorkedExample {
  id: string;
  title: string;
  situation: string;
  sscpMove: string;
  whyItWorks: string;
  cisspBridge: string;
  pitfalls: string[];
}

export interface LessonScenario {
  id: string;
  title: string;
  situation: string;
  signals: string[];
  sscpResponse: string;
  cisspResponse: string;
  ctoHorizon: string;
}

export interface LessonCheckpoint {
  id: string;
  format: "single_select" | "multi_select" | "short_answer";
  prompt: string;
  options?: QuestionOption[];
  correctOptionIds?: string[];
  expectedAnswer: string;
  remediation: string;
  coachingTip: string;
  objectiveId: string;
}

export interface DiagramNode {
  id: string;
  label: string;
  detail: string;
  group: "core" | "support" | "risk" | "bridge";
}

export interface DiagramEdge {
  from: string;
  to: string;
  label: string;
}

export interface DiagramSpec {
  id: string;
  title: string;
  type: "mindmap" | "flow";
  summary: string;
  focusPrompt: string;
  nodes: DiagramNode[];
  edges: DiagramEdge[];
}

export interface StrategicLens {
  title: string;
  businessImpact: string;
  architectureTradeoff: string;
  leadershipPrompt: string;
}

export interface QuestionAnswerLens {
  level: ThinkingLevel;
  title: string;
  answer: string;
  explanation: string;
  focus: string;
}

export interface QuestionBlueprint {
  id: string;
  format: QuestionFormat;
  title: string;
  prompt: string;
  domainIds: SscpDomainId[];
  objectiveIds: string[];
  difficulty: "foundation" | "pressure" | "bridge";
  difficultyLabel: string;
  scenarioContext?: string;
  options?: QuestionOption[];
  correctOptionIds?: string[];
  optionRationales?: OptionRationale[];
  idealAnswer: string;
  answerGuidance: string[];
  answerKeyPhrases: string[];
  strategicTakeaway: string;
  answerLenses: QuestionAnswerLens[];
  citations: SourceCitation[];
  sourceTypes: SourceTrustLevel[];
}

export interface ReviewPanel {
  score: number;
  verdict: string;
  rationale: string;
  strengths: string[];
  gaps: string[];
  nextStep: string;
}

export interface DualReview {
  confidenceLevel: "low" | "medium" | "high";
  correctness: "incorrect" | "partial" | "correct" | "strong";
  confidenceGap: number;
  missedConcepts: string[];
  crossDomainSignals: string[];
  recommendedNextTask: string;
  bestAnswerRationale: string;
  distractorWarnings: string[];
  thinkingCorrection: string;
  sscpTakeaway: string;
  cisspTakeaway: string;
  sscpReview: ReviewPanel;
  cisspReview: ReviewPanel;
  citations: SourceCitation[];
  sourceTypes: SourceTrustLevel[];
}

export interface PlanRequest {
  profile: LearnerProfile;
  mastery: MasterySnapshot;
}

export interface TeachResponse {
  generatedAt: string;
  domain: SscpDomain;
  objectiveFocus: SscpObjective[];
  lessonSummary: string;
  lessonSections: Array<{ title: string; body: string }>;
  glossary: string[];
  studyTips: string[];
  flashcards: Flashcard[];
  workedExamples: WorkedExample[];
  lessonScenarios: LessonScenario[];
  checkpointQuestions: LessonCheckpoint[];
  diagramSpecs: DiagramSpec[];
  strategicLens: StrategicLens;
  noteReferences: ImportedNoteChunk[];
  citations: SourceCitation[];
  sourceTypes: SourceTrustLevel[];
  confidenceLevel: "low" | "medium" | "high";
  recommendedNextTask: string;
  sscpReview: ReviewPanel;
  cisspReview: ReviewPanel;
  missedConcepts: string[];
}

export interface DrillRequest {
  domainIds: SscpDomainId[];
  mode: "mixed" | "multiple_choice" | "short_answer" | "scenario";
  count: number;
  difficulty: "foundation" | "pressure" | "bridge";
  thinkingLevel?: ThinkingLevel;
  domainMode?: DomainStudyMode;
  topicHint?: string;
  generationNonce?: number;
}

export interface DrillResponse {
  generatedAt: string;
  questions: QuestionBlueprint[];
  citations: SourceCitation[];
  sourceTypes: SourceTrustLevel[];
  confidenceLevel: "low" | "medium" | "high";
  sscpReview: ReviewPanel;
  cisspReview: ReviewPanel;
  missedConcepts: string[];
  recommendedNextTask: string;
  selectedLevel: ThinkingLevel;
  domainMode: DomainStudyMode;
}

export interface QuestionAttempt {
  questionId: string;
  answer: string | string[];
  confidence: number;
}

export interface MockResponse {
  generatedAt: string;
  length: "mini" | "full";
  durationMinutes: number;
  questions: QuestionBlueprint[];
  guidance: string;
  citations: SourceCitation[];
  sourceTypes: SourceTrustLevel[];
  confidenceLevel: "low" | "medium" | "high";
  sscpReview: ReviewPanel;
  cisspReview: ReviewPanel;
  missedConcepts: string[];
  recommendedNextTask: string;
}

export interface NarrationRequest {
  text: string;
  voice?: "alloy" | "ash" | "ballad" | "coral" | "echo" | "sage" | "shimmer" | "verse" | "marin" | "cedar";
  speed?: number;
  instructions?: string;
  format?: "mp3" | "wav" | "aac";
}

export interface ExtensionCapture {
  id: string;
  title: string;
  url: string;
  selectionText?: string;
  pageText?: string;
  createdAt: string;
  processed?: boolean;
}

export interface CaptureStudyAid {
  summary: string;
  flashcards: Flashcard[];
  scenarioPrompt: string;
  strategicPrompt: string;
}

export interface ActionHealthCheck {
  id: string;
  workspace: "global" | "plan" | "learn" | "drill" | "resources" | "library" | "extension";
  label: string;
  expectedOutcome: string;
}
