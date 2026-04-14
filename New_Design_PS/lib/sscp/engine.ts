import {
  CURATED_RESOURCES,
  SOURCE_POLICY,
  SSCP_DOMAINS,
  SSCP_TO_CISSP_BRIDGE,
  getCisspDomainsForSscp,
  getSscpDomain,
} from "@/lib/sscp/catalog";
import {
  DomainStudyMode,
  DiagramSpec,
  DrillRequest,
  DomainMastery,
  DrillResponse,
  Flashcard,
  ImportedNoteChunk,
  LessonCheckpoint,
  LessonScenario,
  LearningResource,
  MasterySnapshot,
  QuestionAnswerLens,
  OptionRationale,
  PlanRequest,
  QuestionBlueprint,
  QuestionFormat,
  ReviewPanel,
  StrategicLens,
  SourceCitation,
  SourceTrustLevel,
  SscpDomain,
  SscpDomainId,
  StudyTask,
  StudySprintPlan,
  TeachResponse,
  ThinkingLevel,
  WorkedExample,
} from "@/lib/sscp/types";

const TRUST_RANK: Record<SourceTrustLevel, number> = {
  official: 0,
  trusted_live: 1,
  user_notes: 2,
};

function reviewPanel(
  score: number,
  verdict: string,
  rationale: string,
  strengths: string[],
  gaps: string[],
  nextStep: string,
): ReviewPanel {
  return {
    score: Math.max(0, Math.min(100, Math.round(score))),
    verdict,
    rationale,
    strengths,
    gaps,
    nextStep,
  };
}

export function sortCitations(citations: SourceCitation[]): SourceCitation[] {
  return [...citations].sort((left, right) => {
    const trustGap = TRUST_RANK[left.trustLevel] - TRUST_RANK[right.trustLevel];
    if (trustGap !== 0) return trustGap;
    return left.label.localeCompare(right.label);
  });
}

export function inferConfidenceLevel(citations: SourceCitation[]): "low" | "medium" | "high" {
  const trustLevels = new Set(citations.map((citation) => citation.trustLevel));
  if (trustLevels.has("official")) return "high";
  if (trustLevels.has("trusted_live")) return "medium";
  return "low";
}

function uniqueStrings(items: string[]): string[] {
  return [...new Set(items.filter(Boolean))];
}

function noteCitation(note: ImportedNoteChunk): SourceCitation {
  return {
    id: `note-${note.id}`,
    label: `${note.fileName} · ${note.sectionLabel}`,
    sourceName: note.fileName,
    trustLevel: "user_notes",
    note: "Local PDF study corpus",
  };
}

function toFileUrl(fileName: string): string {
  const baseDir = (
    process.env.SSCP_COACH_DOC_DIR ??
    "C:\\Users\\aiuser\\Desktop\\SSCP-CISSP-Coach\\doc"
  ).replace(/\\/g, "/");
  return `file:///${encodeURI(`${baseDir}/${fileName}`)}`;
}

function getTrustedResources(
  domainId: SscpDomainId,
  topicHint?: string,
): LearningResource[] {
  const normalizedHint = topicHint?.toLowerCase().trim();
  const matching = CURATED_RESOURCES.filter((resource) => resource.domainIds.includes(domainId));

  if (!normalizedHint) {
    return matching.slice(0, 3);
  }

  const scored = matching
    .map((resource) => {
      const haystack = `${resource.title} ${resource.summary} ${resource.whyItMatters} ${resource.sscpFit} ${resource.cisspBridgeValue}`.toLowerCase();
      const score = normalizedHint
        .split(/[, ]+/)
        .filter((token) => token.length >= 3)
        .reduce((sum, token) => (haystack.includes(token) ? sum + 1 : sum), 0);
      return { resource, score };
    })
    .sort((left, right) => right.score - left.score);

  return scored.map((entry) => entry.resource).slice(0, 3);
}

function getPdfResources(
  domainId: SscpDomainId,
  notes: ImportedNoteChunk[],
): LearningResource[] {
  return notes
    .filter((note) => note.domainId === domainId)
    .slice(0, 4)
    .map((note, index) => ({
      id: `${domainId}-pdf-resource-${index + 1}`,
      title: `${note.fileName} · ${note.sectionLabel}`,
      url: toFileUrl(note.fileName),
      format: "guide" as const,
      sourceName: note.fileName,
      sourceType: "user_notes" as const,
      domainIds: [domainId],
      difficulty: index === 0 ? "foundation" as const : index === 1 ? "intermediate" as const : "advanced" as const,
      timeToConsume: "10-20 min",
      sscpFit: `Use this excerpt to reinforce ${getSscpDomain(domainId).title} with direct vocabulary, examples, and operational framing.`,
      cisspBridgeValue: "Translate the same excerpt into governance, architecture, or enterprise-risk language after you understand the core control move.",
      summary: note.excerpt.slice(0, 260),
      whyItMatters: `This section is part of the local PDF study corpus and gives you more depth on ${note.title}.`,
      strategicValue: "Use the excerpt to practice moving from tactical controls to broader business, design, and leadership consequences.",
      readableText: note.excerpt,
      citations: [noteCitation(note)],
    }));
}

function getFocusResources(
  domainId: SscpDomainId,
  notes: ImportedNoteChunk[],
  topicHint?: string,
): LearningResource[] {
  return [
    ...getTrustedResources(domainId, topicHint),
    ...getPdfResources(domainId, notes),
  ].slice(0, 6);
}

const DOMAIN_BLEND_MAP: Record<SscpDomainId, SscpDomainId[]> = {
  "security-concepts-practices": ["risk-identification-monitoring-analysis", "access-controls"],
  "access-controls": ["network-communications-security", "security-concepts-practices"],
  "risk-identification-monitoring-analysis": ["incident-response-recovery", "security-concepts-practices"],
  "incident-response-recovery": ["risk-identification-monitoring-analysis", "network-communications-security"],
  cryptography: ["network-communications-security", "systems-application-security"],
  "network-communications-security": ["access-controls", "cryptography"],
  "systems-application-security": ["cryptography", "risk-identification-monitoring-analysis"],
};

function blendDomains(
  primaryDomainId: SscpDomainId,
  requestedDomainIds: SscpDomainId[],
  domainMode: DomainStudyMode,
  index: number,
  salt = 0,
): SscpDomainId[] {
  if (domainMode === "single") {
    return [primaryDomainId];
  }

  const requestedPartner =
    requestedDomainIds.length > 1
      ? requestedDomainIds[(index + salt + 1) % requestedDomainIds.length]
      : undefined;
  const mappedPartner =
    DOMAIN_BLEND_MAP[primaryDomainId][(index + salt) % DOMAIN_BLEND_MAP[primaryDomainId].length];
  const partner = requestedPartner && requestedPartner !== primaryDomainId
    ? requestedPartner
    : mappedPartner;

  return [...new Set([primaryDomainId, partner])];
}

function normalizeSeed(seed: number) {
  return Math.abs(Math.trunc(seed)) || 1;
}

function hashText(value?: string) {
  if (!value) return 0;

  let hash = 0;
  for (const char of value) {
    hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  }
  return hash;
}

function rotateArray<T>(items: T[], offset: number) {
  if (items.length <= 1) return [...items];
  const safeOffset = ((offset % items.length) + items.length) % items.length;
  return [...items.slice(safeOffset), ...items.slice(0, safeOffset)];
}

function buildObjectiveCue(objective: { title: string; keywords: string[] }) {
  const focus = objective.keywords.slice(0, 2).join(" and ");
  if (focus) {
    return `The priority is to protect ${focus}.`;
  }

  return `The priority is to satisfy the objective "${objective.title}".`;
}

function buildAnswerLenses(
  domainIds: SscpDomainId[],
  objectiveTitle: string,
  strategicTakeaway: string,
  noteAnchor?: ImportedNoteChunk,
): QuestionAnswerLens[] {
  const primary = getSscpDomain(domainIds[0]);
  const partner = domainIds[1] ? getSscpDomain(domainIds[1]) : null;
  const reinforcement = noteAnchor
    ? " Compare your answer with the supplemental PDF notes after you commit to a choice."
    : "";

  return [
    {
      level: "sscp",
      title: "An SSCP may answer like this",
      answer: `Start with the immediate control action that best satisfies the objective "${objectiveTitle}" in ${primary.title}. Explain how that action reduces risk right now${partner ? ` while coordinating with ${partner.title.toLowerCase()}` : ""}.`,
      explanation: `This answer wins at the SSCP level because it stays operational, names the control move first, and avoids drifting into abstract theory.${reinforcement}`,
      focus: "Immediate control action, operational evidence, and correct practitioner judgment.",
    },
    {
      level: "cissp",
      title: "A CISSP may answer like this",
      answer: `Take the SSCP-correct control action, then broaden it into risk, governance, and architecture language. Show how ${primary.title.toLowerCase()}${partner ? ` and ${partner.title.toLowerCase()}` : ""} interact and what residual risk remains if the control is weak.`,
      explanation: "This answer is stronger at the CISSP level because it connects the tactical control decision to enterprise-wide design, policy, and tradeoff reasoning.",
      focus: "Risk framing, control interaction, governance, and architectural consequence.",
    },
    {
      level: "cto",
      title: "A CTO may answer like this",
      answer: `Frame the same issue as a leadership decision: what gets fixed immediately, what gets standardized across teams, what gets measured, and how the business impact is communicated. ${strategicTakeaway}`,
      explanation: "This lens goes beyond certification depth and treats the question like an executive security and technology leadership problem that affects roadmaps, accountability, and investment.",
      focus: "Business impact, operating model, standardization, measurement, and stakeholder communication.",
    },
  ];
}

type ExamScenarioSeed = {
  stem: string;
  context: string;
  bestAction: string;
  secondAction: string;
  distractorOne: string;
  distractorTwo: string;
  distractorThree: string;
  bestActionReason: string;
};

type QuestionBuildOptions = {
  objectiveOffset: number;
  noteOffset: number;
  trustedOffset: number;
  variantIndex: number;
};

function formatQuestionTitle(index: number, format: QuestionFormat): string {
  const label =
    format === "single_select"
      ? "Best-answer question"
      : format === "multi_select"
        ? "Multi-select question"
        : format === "scenario"
          ? "Scenario question"
          : "Short-answer question";
  return `Question ${index + 1} · ${label}`;
}

function buildPartnerComplication(partnerDomain: SscpDomain | null): string {
  if (!partnerDomain) return "";

  switch (partnerDomain.id) {
    case "security-concepts-practices":
      return " The decision also affects policy compliance, accountability, and separation-of-duties expectations.";
    case "access-controls":
      return " Identity lifecycle mistakes and excessive privileges could make the impact worse.";
    case "risk-identification-monitoring-analysis":
      return " Monitoring gaps make it difficult to tell whether the weakness has already been exploited.";
    case "incident-response-recovery":
      return " If the response is mishandled, the issue could escalate into a formal incident that requires evidence preservation.";
    case "cryptography":
      return " Sensitive data protection and certificate or key-management practices are also involved.";
    case "network-communications-security":
      return " Network exposure and possible lateral movement increase the blast radius if the weakness is exploited.";
    case "systems-application-security":
      return " Application or endpoint hardening weaknesses also contribute to the risk picture.";
    default:
      return "";
  }
}

function buildExamScenarioSeed(
  domain: SscpDomain,
  partnerDomain: SscpDomain | null,
  variantIndex: number,
): ExamScenarioSeed {
  const partnerComplication = buildPartnerComplication(partnerDomain);
  const pressureAddons = [
    {
      stem: " The issue appears during a high-pressure business period, so the team is tempted to prioritize speed over control discipline.",
      context: "Business pressure is high, but the answer still has to be defensible and evidence-based.",
    },
    {
      stem: " A recent audit already noted a related weakness, so repeating the mistake would increase scrutiny.",
      context: "The organization needs a response that stands up to review, not just a fast workaround.",
    },
    {
      stem: " A third-party partner depends on the affected service, so availability matters along with security.",
      context: "The best answer must balance operational continuity with immediate risk reduction.",
    },
    {
      stem: " Leadership expects an answer quickly and will want to know why this decision is the strongest one.",
      context: "The decision has to work operationally now and remain easy to justify afterward.",
    },
  ];
  const addon = pressureAddons[variantIndex % pressureAddons.length];

  switch (domain.id) {
    case "security-concepts-practices":
      return {
        stem: `A security administrator is asked to push an urgent production change without the approved change-control and review process so a business unit can hit a deadline.${partnerComplication}${addon.stem}`,
        context: `The organization expects documented approval, accountability, and evidence for production changes. ${addon.context}`,
        bestAction:
          "Follow the approved change and escalation process, document the risk, and obtain proper authorization before implementation.",
        secondAction:
          "Record the business justification, affected assets, and compensating controls so the change can be reviewed and audited afterward.",
        distractorOne: "Implement the change immediately and update the records later if no issue is reported.",
        distractorTwo: "Let the business owner approve the change verbally without formal security review.",
        distractorThree: "Ignore the request completely and wait for the next formal meeting without documenting the risk.",
        bestActionReason:
          "it preserves accountability, follows control expectations, and still allows the organization to handle the business request through the proper path",
      };
    case "access-controls":
      return {
        stem: `A contractor's project ended last week, but the contractor still has active VPN access and membership in a privileged support group.${partnerComplication}${addon.stem}`,
        context: `The account no longer has a valid business need, and the privileged membership increases risk. ${addon.context}`,
        bestAction:
          "Remove the unnecessary access immediately, verify why deprovisioning failed, and review related privileged entitlements.",
        secondAction:
          "Confirm account ownership and approval records, then search for similar lifecycle gaps in other accounts.",
        distractorOne: "Leave the access in place until the next quarterly access review to avoid disrupting operations.",
        distractorTwo: "Convert the account to a shared support account so the team keeps access continuity.",
        distractorThree: "Keep the access active but ask the manager to remember to submit a cleanup request later.",
        bestActionReason:
          "it applies least privilege immediately, closes the lifecycle gap, and reduces the chance of unauthorized use",
      };
    case "risk-identification-monitoring-analysis":
      return {
        stem: `A vulnerability scan identifies a critical flaw on an internet-facing server that stores sensitive data, and public exploit code is available.${partnerComplication}${addon.stem}`,
        context: `The system owner wants to postpone remediation until the next maintenance window, but the exposure is active now. ${addon.context}`,
        bestAction:
          "Validate the exposure, prioritize treatment based on likelihood and impact, and implement remediation or compensating controls immediately.",
        secondAction:
          "Document the risk decision and strengthen monitoring so exploitation attempts can be detected while treatment is underway.",
        distractorOne: "Wait for the next scheduled maintenance window without changing the current exposure.",
        distractorTwo: "Close the scan ticket because exploitation has not yet been confirmed in your environment.",
        distractorThree: "Downgrade the issue because business owners dislike emergency remediation work.",
        bestActionReason:
          "it uses evidence-based risk treatment and addresses an active high-likelihood, high-impact exposure instead of delaying action",
      };
    case "incident-response-recovery":
      return {
        stem: `The SOC detects suspicious outbound connections from a finance workstation, and the user reports files becoming inaccessible.${partnerComplication}${addon.stem}`,
        context: `Time matters, but evidence may be needed for investigation, containment, and recovery. ${addon.context}`,
        bestAction:
          "Contain the affected system, preserve evidence, and follow the incident response process for analysis and recovery.",
        secondAction:
          "Notify the incident team and begin documented triage so scope, impact, and recovery priorities are clear.",
        distractorOne: "Reboot the workstation immediately and return it to the user before documenting anything.",
        distractorTwo: "Ignore the alert until multiple users report the same issue.",
        distractorThree: "Start rebuilding the workstation without collecting evidence or coordinating with the incident process.",
        bestActionReason:
          "it reduces ongoing harm while preserving the evidence and process discipline needed for a proper investigation and recovery",
      };
    case "cryptography":
      return {
        stem: `The team discovers that private keys for a production TLS certificate are stored in a shared administrator folder accessible by multiple staff members.${partnerComplication}${addon.stem}`,
        context: `The certificate protects a customer-facing service, so confidentiality and trust are at stake. ${addon.context}`,
        bestAction:
          "Move key material into approved protected storage, restrict access, and rotate affected keys or certificates as needed.",
        secondAction:
          "Review key-management practices and access logs to determine potential exposure and prevent recurrence.",
        distractorOne: "Leave the keys where they are because only internal administrators can access the folder.",
        distractorTwo: "Copy the keys to more shared locations so administrators always have a backup available.",
        distractorThree: "Delay any action until the next certificate renewal cycle because the service is still online.",
        bestActionReason:
          "it protects sensitive key material immediately and treats possible compromise as a key-management problem that needs controlled remediation",
      };
    case "network-communications-security":
      return {
        stem: `Guest wireless users can currently reach the same network segment as employee workstations and point-of-sale devices.${partnerComplication}${addon.stem}`,
        context: `The business wants guest access to remain available without exposing internal systems to unnecessary risk. ${addon.context}`,
        bestAction:
          "Segment guest traffic from internal networks and enforce only the minimal access required for the guest service.",
        secondAction:
          "Validate firewall, ACL, and monitoring rules so the segmentation control is actually effective in operation.",
        distractorOne: "Keep the flat network design because adding segmentation could inconvenience guests.",
        distractorTwo: "Turn off all wireless access permanently instead of applying a targeted control.",
        distractorThree: "Rely on endpoint antivirus alone to protect internal systems from guest traffic.",
        bestActionReason:
          "it reduces attack surface and lateral movement risk while preserving the business need through controlled connectivity",
      };
    case "systems-application-security":
      return {
        stem: `A release candidate passes functional testing, but the latest security scan shows a high-severity injection weakness in an authenticated page.${partnerComplication}${addon.stem}`,
        context: `The product team wants to ship today to meet a customer commitment, but the weakness is still present. ${addon.context}`,
        bestAction:
          "Block the vulnerable release, remediate the flaw, and verify the fix through security testing before deployment.",
        secondAction:
          "Assess related components for similar weaknesses and track the remediation through change and release controls.",
        distractorOne: "Deploy the release now and plan to fix the weakness in the next sprint if no exploit is reported.",
        distractorTwo: "Suppress the finding because only authenticated users can reach the vulnerable page.",
        distractorThree: "Remove the scan result from the report so the release process can continue on schedule.",
        bestActionReason:
          "it prevents a known exploitable weakness from reaching production and keeps security verification inside the system lifecycle",
      };
    default:
      return {
        stem: `A security team identifies a control weakness that creates active risk in a production environment.${partnerComplication}${addon.stem}`,
        context: `The organization needs a response that reduces risk now and preserves evidence for follow-up. ${addon.context}`,
        bestAction:
          "Apply the direct control response, document the decision, and collect the evidence needed for follow-up review.",
        secondAction:
          "Confirm scope and validate whether similar weaknesses exist elsewhere in the environment.",
        distractorOne: "Wait for a perfect long-term redesign before taking any immediate action.",
        distractorTwo: "Choose convenience over control because the issue has not yet caused a confirmed incident.",
        distractorThree: "Escalate the issue without gathering enough evidence to support a sound decision.",
        bestActionReason:
          "it addresses the immediate weakness while keeping the response disciplined and evidence-based",
      };
  }
}

function buildFlashcards(
  domainId: SscpDomainId,
  noteReferences: ImportedNoteChunk[],
  resourceRefs: LearningResource[],
): Flashcard[] {
  const domain = getSscpDomain(domainId);
  const objectiveCards = domain.objectives.slice(0, 4).map((objective, index) => ({
    id: `${domainId}-objective-card-${index + 1}`,
    front: `What is the SSCP move behind "${objective.title}"?`,
    back: `${objective.summary} Keywords to anchor: ${objective.keywords.join(", ")}.`,
    hint: "Name the direct control action before you explain the broader theory.",
    cue: "Control action -> risk reduced -> evidence produced",
  }));

  const noteCard = noteReferences[0]
    ? [
        {
          id: `${domainId}-note-card`,
          front: `How should you use the note "${noteReferences[0].title}" without over-trusting it?`,
          back: `Use it as reinforcement only. Let the mapped lesson objective organize your thinking, and use the note only when it cleanly supports that same control idea.`,
          hint: "Ask whether the note reinforces or competes with the mapped lesson objective.",
          cue: "Objective first, note second",
        },
      ]
    : [];

  const resourceCard = resourceRefs[0]
    ? [
        {
          id: `${domainId}-resource-card`,
          front: `Why does ${resourceRefs[0].title} matter beyond SSCP memorization?`,
          back: `${resourceRefs[0].summary} Strategic value: ${resourceRefs[0].strategicValue ?? resourceRefs[0].whyItMatters}`,
          hint: "Connect the reading to one control family and one business concern.",
          cue: "SSCP precision -> CISSP/CTO framing",
        },
      ]
    : [];

  return [...objectiveCards, ...noteCard, ...resourceCard];
}

function buildWorkedExamples(
  domainId: SscpDomainId,
  noteReferences: ImportedNoteChunk[],
  resourceRefs: LearningResource[],
): WorkedExample[] {
  const domain = getSscpDomain(domainId);
  const firstObjective = domain.objectives[0];
  const secondObjective = domain.objectives[1] ?? firstObjective;
  const noteExcerpt = noteReferences[0]?.excerpt ?? domain.summary;
  const resourceTitle = resourceRefs[0]?.title ?? "a trusted operational guide";

  return [
    {
      id: `${domainId}-example-1`,
      title: `${firstObjective.title} in the real world`,
      situation: `A team needs a quick security decision under pressure. The right move is the one that most directly reinforces ${firstObjective.title.toLowerCase()} while still producing evidence and accountability.`,
      sscpMove: `Choose the control action that directly supports ${firstObjective.title.toLowerCase()}, document the decision, and reduce immediate risk before chasing broader redesign.`,
      whyItWorks: `It keeps the answer operationally correct, tied to the objective, and focused on the control principle instead of vague security language.`,
      cisspBridge: `Then widen the frame: ask how this decision changes enterprise risk, policy enforcement, or architectural consistency.`,
      pitfalls: [
        "Jumping straight to long-term strategy without fixing the immediate control gap.",
        "Naming a concept without showing the operational action behind it.",
      ],
    },
    {
      id: `${domainId}-example-2`,
      title: `Using notes and trusted guidance together`,
      situation: `Your notes mention: "${noteExcerpt.slice(0, 160)}..." but ${resourceTitle} frames the topic through broader control reasoning.`,
      sscpMove: `Use the notes to remember the vocabulary and sequence, but answer from the mapped control objective and the direct operational need represented by ${secondObjective.title.toLowerCase()}.`,
      whyItWorks: "It protects you from drifting into unsupported or overstated claims while still benefiting from your own reinforcement material.",
      cisspBridge: `Senior-level answers go one step further and explain why the same control logic matters to governance, resilience, or enterprise architecture.`,
      pitfalls: [
        "Treating notes as authoritative when they conflict with canonical framing.",
        "Repeating memorized language without tying it to risk reduction.",
      ],
    },
  ];
}

function buildLessonScenarios(
  domainId: SscpDomainId,
  noteReferences: ImportedNoteChunk[],
): LessonScenario[] {
  const domain = getSscpDomain(domainId);
  const primary = domain.objectives[0];
  const secondary = domain.objectives[1] ?? primary;

  return [
    {
      id: `${domainId}-scenario-1`,
      title: `${domain.title} shift-change scenario`,
      situation: `You inherit an operational issue linked to ${primary.title.toLowerCase()}. The previous shift left an incomplete control trail and the business wants speed.`,
      signals: uniqueStrings([
        ...primary.keywords.slice(0, 3),
        noteReferences[0]?.keywords[0] ?? "evidence",
        "accountability",
      ]),
      sscpResponse: `State the direct control action, explain how it reinforces ${primary.title.toLowerCase()}, and document the evidence or ownership needed before closing the issue.`,
      cisspResponse: "Add one sentence on enterprise risk, policy alignment, or architectural knock-on effects if this pattern repeats.",
      ctoHorizon: "Ask which part of the process, platform, or governance model allowed the gap to recur in the first place.",
    },
    {
      id: `${domainId}-scenario-2`,
      title: `${domain.title} pressure-test scenario`,
      situation: `An executive asks for a fast answer tied to ${secondary.title.toLowerCase()}, but the operational team is split between convenience and control strength.`,
      signals: uniqueStrings([
        ...secondary.keywords.slice(0, 3),
        "tradeoff",
        "business pressure",
      ]),
      sscpResponse: `Choose the control path that most directly supports ${secondary.title.toLowerCase()} and explain why weaker options fail operationally.`,
      cisspResponse: "Show what a broader security leader would say about tradeoffs, residual risk, and accountability.",
      ctoHorizon: "Translate the same issue into program language: standards, architecture guardrails, metrics, and executive communication.",
    },
  ];
}

function buildLessonCheckpoints(domainId: SscpDomainId): LessonCheckpoint[] {
  const domain = getSscpDomain(domainId);
  const firstObjective = domain.objectives[0];
  const secondObjective = domain.objectives[1] ?? firstObjective;
  const thirdObjective = domain.objectives[2] ?? secondObjective;
  const scenarioSeed = buildExamScenarioSeed(domain, null, 2);

  return [
    {
      id: `${domainId}-checkpoint-1`,
      format: "single_select",
      prompt: `Which answer style best matches SSCP thinking for ${firstObjective.title.toLowerCase()}?`,
      options: [
        {
          id: "a",
          label: "A",
          text: "Name the immediate control action, the principle behind it, and the risk it reduces.",
        },
        {
          id: "b",
          label: "B",
          text: "Discuss only long-range strategy and avoid operational specifics.",
        },
        {
          id: "c",
          label: "C",
          text: "Repeat a keyword without tying it to any action or evidence.",
        },
        {
          id: "d",
          label: "D",
          text: "Prefer convenience over accountability while the issue is still active.",
        },
      ],
      correctOptionIds: ["a"],
      expectedAnswer:
        "A is strongest because SSCP answers should be operationally direct, tied to the correct control principle, and explicit about the risk they reduce.",
      remediation:
        "Revisit the core concept and the worked example before moving to the next checkpoint.",
      coachingTip:
        "If you cannot name the control action, you do not yet own the objective.",
      objectiveId: firstObjective.id,
    },
    {
      id: `${domainId}-checkpoint-2`,
      format: "multi_select",
      prompt: `${scenarioSeed.stem} Which TWO actions should the team take first? Select all that apply.`,
      options: [
        { id: "a", label: "A", text: scenarioSeed.bestAction },
        { id: "b", label: "B", text: scenarioSeed.secondAction },
        { id: "c", label: "C", text: scenarioSeed.distractorOne },
        { id: "d", label: "D", text: scenarioSeed.distractorTwo },
      ],
      correctOptionIds: ["a", "b"],
      expectedAnswer: `Both A and B are correct. A is the primary control move because ${scenarioSeed.bestActionReason}. B adds the evidence and follow-through that makes the response defensible and repeatable. C and D are distractors that delay the correct response, trade control discipline for convenience, or leave risk active.`,
      remediation:
        "Look for the option that directly reduces the active risk first, then look for the option that produces evidence or strengthens accountability. Distractors typically delay action or substitute convenience for control.",
      coachingTip:
        "Multi-select questions test whether you can identify both the immediate control move and the supporting action that makes it stick. Selecting only one correct option is a partial miss.",
      objectiveId: thirdObjective.id,
    },
    {
      id: `${domainId}-checkpoint-3`,
      format: "short_answer",
      prompt: `In 2-4 sentences, explain why ${secondObjective.title.toLowerCase()} matters in a real operational environment.`,
      expectedAnswer: `A strong answer states the control goal behind ${secondObjective.title.toLowerCase()}, the operational action that supports it, and one concrete risk or failure mode that grows if it is ignored.`,
      remediation:
        "Use one flashcard and one scenario from this lesson, then answer again in your own words.",
      coachingTip:
        "Keep it tight: control goal, action, consequence.",
      objectiveId: secondObjective.id,
    },
  ];
}

function buildDiagramSpecs(
  domainId: SscpDomainId,
  noteReferences: ImportedNoteChunk[],
  resourceRefs: LearningResource[],
): DiagramSpec[] {
  const domain = getSscpDomain(domainId);
  const bridges = getCisspDomainsForSscp(domainId);
  const primaryKeywords = uniqueStrings(domain.objectives.flatMap((objective) => objective.keywords)).slice(0, 4);
  const resource = resourceRefs[0];

  return [
    {
      id: `${domainId}-diagram-map`,
      title: `${domain.title} memory map`,
      type: "mindmap",
      summary: "Click the nodes to see how the operational objective scales into broader reasoning.",
      focusPrompt: "Start at the domain, then trace one branch from control action to business consequence.",
      nodes: [
        {
          id: "core-domain",
          label: domain.title,
          detail: domain.summary,
          group: "core",
        },
        ...primaryKeywords.map((keyword, index) => ({
          id: `keyword-${index + 1}`,
          label: keyword,
          detail: `Treat ${keyword} as a retrieval anchor for one SSCP action and one risk consequence.`,
          group: "support" as const,
        })),
        {
          id: "notes",
          label: "User notes",
          detail: noteReferences[0]
            ? `Reinforcement cue: ${noteReferences[0].title}`
            : "Import notes to add local reinforcement cues.",
          group: "risk",
        },
        {
          id: "bridge",
          label: "CISSP bridge",
          detail: `Scale the same concept into ${bridges.map((item) => item.title).join(", ")}.`,
          group: "bridge",
        },
      ],
      edges: [
        ...primaryKeywords.map((_, index) => ({
          from: "core-domain",
          to: `keyword-${index + 1}`,
          label: "retrieval cue",
        })),
        { from: "core-domain", to: "notes", label: "reinforce, do not override" },
        { from: "core-domain", to: "bridge", label: "expand into enterprise thinking" },
      ],
    },
    {
      id: `${domainId}-diagram-flow`,
      title: `${domain.title} decision flow`,
      type: "flow",
      summary: "Use this path when you need to explain a real scenario under time pressure.",
      focusPrompt: "Walk left to right: signal, control, evidence, escalation, strategy.",
      nodes: [
        {
          id: "signal",
          label: "Signal",
          detail: `Spot the condition tied to ${domain.objectives[0].title.toLowerCase()}.`,
          group: "risk",
        },
        {
          id: "control",
          label: "Control action",
          detail: "Choose the operational move that most directly reduces risk.",
          group: "core",
        },
        {
          id: "evidence",
          label: "Evidence",
          detail: "Show accountability, logging, ownership, or measurable proof.",
          group: "support",
        },
        {
          id: "bridge",
          label: "Bridge sentence",
          detail: "Add one statement on governance, architecture, or enterprise impact.",
          group: "bridge",
        },
        {
          id: "resource",
          label: resource?.sourceName ?? "Trusted guide",
          detail: resource
            ? `${resource.title} gives you current reinforcement for this reasoning path.`
            : "Refresh resources to pull in a current guide for this domain.",
          group: "support",
        },
      ],
      edges: [
        { from: "signal", to: "control", label: "triage fast" },
        { from: "control", to: "evidence", label: "prove the move" },
        { from: "evidence", to: "bridge", label: "explain the bigger consequence" },
        { from: "bridge", to: "resource", label: "reinforce with trusted reading" },
      ],
    },
  ];
}

function buildStrategicLens(domainId: SscpDomainId): StrategicLens {
  const domain = getSscpDomain(domainId);
  const bridges = getCisspDomainsForSscp(domainId);
  return {
    title: `${domain.title} strategic lens`,
    businessImpact:
      "Translate the control into uptime, trust, auditability, legal exposure, or customer impact instead of leaving it as a technical point.",
    architectureTradeoff: `Use ${bridges.map((item) => item.title).join(" and ")} to explain how tactical controls either scale cleanly or create future friction.`,
    leadershipPrompt:
      "If this pattern showed up across multiple teams, what would you standardize, what would you measure, and what would you escalate to leadership?",
  };
}

export function createEmptyMasterySnapshot(): MasterySnapshot {
  return {
    overallReadiness: 48,
    cisspBridgeReadiness: 32,
    confidenceCalibration: 58,
    recentMocks: [],
    domains: SSCP_DOMAINS.map((domain) => ({
      domainId: domain.id,
      score: 45,
      confidence: 50,
      attempts: 0,
    })),
  };
}

export function normalizeMastery(snapshot?: Partial<MasterySnapshot>): MasterySnapshot {
  const base = createEmptyMasterySnapshot();
  if (!snapshot) return base;

  const domainMap = new Map<string, DomainMastery>();
  for (const domain of base.domains) {
    domainMap.set(domain.domainId, domain);
  }
  for (const item of snapshot.domains ?? []) {
    domainMap.set(item.domainId, {
      domainId: item.domainId,
      score: Math.max(0, Math.min(100, item.score)),
      confidence: Math.max(0, Math.min(100, item.confidence)),
      attempts: Math.max(0, item.attempts),
      lastReviewedAt: item.lastReviewedAt,
    });
  }

  return {
    overallReadiness:
      snapshot.overallReadiness ?? average([...domainMap.values()].map((entry) => entry.score)),
    cisspBridgeReadiness: snapshot.cisspBridgeReadiness ?? base.cisspBridgeReadiness,
    confidenceCalibration: snapshot.confidenceCalibration ?? base.confidenceCalibration,
    recentMocks: snapshot.recentMocks ?? [],
    domains: SSCP_DOMAINS.map((domain) => domainMap.get(domain.id) ?? base.domains[0]),
  };
}

function average(values: number[]): number {
  if (!values.length) return 0;
  return Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);
}

function findWeakDomains(snapshot: MasterySnapshot): SscpDomainId[] {
  return [...snapshot.domains]
    .sort((left, right) => left.score - right.score)
    .slice(0, 3)
    .map((entry) => entry.domainId);
}

export function computeReadiness(snapshot: MasterySnapshot): MasterySnapshot {
  const byWeight = SSCP_DOMAINS.map((domain) => {
    const entry = snapshot.domains.find((item) => item.domainId === domain.id);
    return (entry?.score ?? 0) * domain.weight;
  });
  const overallReadiness = Math.round(byWeight.reduce((sum, value) => sum + value, 0) / 100);

  const bridgeValues = snapshot.domains.map((entry) => {
    const linked = SSCP_TO_CISSP_BRIDGE[entry.domainId].length;
    return entry.score * (1 + linked * 0.05);
  });
  const cisspBridgeReadiness = Math.round(
    Math.min(100, bridgeValues.reduce((sum, value) => sum + value, 0) / bridgeValues.length),
  );

  return {
    ...snapshot,
    overallReadiness,
    cisspBridgeReadiness,
  };
}

export function buildStudyPlan({ profile, mastery }: PlanRequest): StudySprintPlan {
  const normalized = computeReadiness(normalizeMastery(mastery));
  const weakDomains = findWeakDomains(normalized);
  const tasks: StudyTask[] = [
    {
      id: "task-foundation-review",
      title: "Rebuild your weakest concepts with narrated notes",
      phase: "foundation" as const,
      intensity: "steady" as const,
      domainIds: weakDomains.slice(0, 2),
      durationMinutes: Math.max(35, Math.round(profile.weeklyHours * 7)),
      description:
        "Read the mapped lesson objective first, then compare it against both the trusted guides and your imported PDF excerpts until the recurring control language feels natural.",
    },
    {
      id: "task-pressure-drill",
      title: "Timed mixed-format pressure drill",
      phase: "pressure",
      intensity: normalized.overallReadiness >= 70 ? "pressure" : "stretch",
      domainIds: weakDomains,
      durationMinutes: 45,
      description:
        "Complete a timed mix of multiple choice, multi-select, short answer, and scenario questions with confidence tracking turned on.",
    },
    {
      id: "task-bridge-lab",
      title: "CISSP bridge reasoning lab",
      phase: "bridge",
      intensity: "stretch",
      domainIds: [weakDomains[0] ?? "access-controls"],
      durationMinutes: 40,
      description:
        "Take one SSCP-correct answer and rewrite it as a senior-level CISSP answer that adds risk, governance, architecture, or business tradeoffs.",
    },
    {
      id: "task-resource-study",
      title: "Read one trusted study path and narrate the summary",
      phase: "foundation",
      intensity: "steady",
      domainIds: [weakDomains[0] ?? "security-concepts-practices"],
      durationMinutes: 25,
      description:
        "Use the Resources tab to study one trusted guide or PDF excerpt, then use read-aloud to reinforce the key ideas.",
    },
  ];

  const strongest = profile.strengths.length ? profile.strengths[0] : "network-communications-security";
  return {
    generatedAt: new Date().toISOString(),
    readiness: normalized,
    summary:
      normalized.overallReadiness >= 75
        ? "You are ready for harder, mixed-domain pressure work. Keep SSCP precision while expanding your CISSP framing."
        : "You need a strong foundation-first week. Build accuracy on the mapped domain objectives before chasing harder timing pressure.",
    pressureNote:
      normalized.confidenceCalibration < 55
        ? "Your confidence calibration is drifting. The next sprint should force more explanation, not just answer selection."
        : `Keep one confidence-building domain in rotation (${getSscpDomain(strongest).title}) so the pressure work does not become discouraging.`,
    tasks,
  };
}

export function buildTeachResponse(
  domainId: SscpDomainId,
  notes: ImportedNoteChunk[],
): TeachResponse {
  const domain = getSscpDomain(domainId);
  const bridges = getCisspDomainsForSscp(domainId);
  const noteReferences = notes.filter((note) => note.domainId === domainId).slice(0, 4);
  const resourceRefs = getFocusResources(domainId, notes);
  const studyTips = [
    `Start every answer in ${domain.title} with the most direct operational control move.`,
    "If your answer sounds abstract, add the evidence, ownership, or enforcement step.",
    "Use trusted guides for the cleanest framing, then use the PDF corpus to reinforce memory, examples, and vocabulary from the actual study books you selected.",
    "After every SSCP answer, add one sentence on risk, architecture, or leadership impact.",
  ];
  const flashcards = buildFlashcards(domainId, noteReferences, resourceRefs);
  const workedExamples = buildWorkedExamples(domainId, noteReferences, resourceRefs);
  const lessonScenarios = buildLessonScenarios(domainId, noteReferences);
  const checkpointQuestions = buildLessonCheckpoints(domainId);
  const diagramSpecs = buildDiagramSpecs(domainId, noteReferences, resourceRefs);
  const strategicLens = buildStrategicLens(domainId);
  const citations = sortCitations([
    domain.officialCitation,
    ...resourceRefs.flatMap((resource) => resource.citations),
    ...noteReferences.map((note) => noteCitation(note)),
  ]);
  const lessonAnchor = noteReferences[0]?.excerpt ?? domain.summary;
  const secondaryAnchor = noteReferences[1]?.excerpt ?? workedExamples[0].whyItWorks;

  return {
    generatedAt: new Date().toISOString(),
    domain,
    objectiveFocus: domain.objectives,
    lessonSummary: `${domain.title} is grounded here in the official SSCP/CISSP domain framing, strengthened by trusted study resources, and reinforced with your local PDF study corpus. Learn the direct SSCP control logic first, then widen the same answer into CISSP-level risk, architecture, and leadership reasoning.`,
    lessonSections: [
      {
        title: "Core concept",
        body: `${domain.summary} ${lessonAnchor.slice(0, 220)} Focus on the immediate control move, the principle behind it, and the risk it changes.`,
      },
      {
        title: "Why it matters",
        body: `${secondaryAnchor.slice(0, 260)} When you answer CISSP-style, extend the same idea into ${bridges.map((item) => item.title).join(", ")}. Ask what risk is reduced, what control family is involved, and what business or architectural tradeoff appears.`,
      },
      {
        title: "Worked example",
        body: workedExamples[0].whyItWorks,
      },
      {
        title: "Real-world scenario",
        body: lessonScenarios[0].situation,
      },
      {
        title: "How to use trusted guides and your PDF sources safely",
        body: noteReferences.length
          ? "Use the trusted guides and the official domain framing to set the baseline, then use the PDF excerpts as reinforcement for vocabulary, examples, and reasoning patterns before proving understanding in flashcards, checkpoints, and scenario drills."
          : "No PDF chunks were attached yet for this domain. The tutor can still teach from the official domain framing and trusted study resources, and you can add local PDF reinforcement from the Library tab.",
      },
      {
        title: "CTO horizon",
        body: strategicLens.leadershipPrompt,
      },
    ],
    glossary: domain.glossary,
    studyTips,
    flashcards,
    workedExamples,
    lessonScenarios,
    checkpointQuestions,
    diagramSpecs,
    strategicLens,
    noteReferences,
    citations,
    sourceTypes: [...new Set(citations.map((citation) => citation.trustLevel))],
    confidenceLevel: inferConfidenceLevel(citations),
    recommendedNextTask: `Work through the flashcards, clear the checkpoints, then launch a scenario drill in ${domain.title} and answer at least one prompt with both SSCP precision and CISSP depth.`,
    sscpReview: reviewPanel(
      88,
      "Book-grounded and operational",
      `This lesson stays anchored to the official domain framing for ${domain.title}, adds trusted study paths, and uses your local PDF study corpus as reinforcement instead of guesswork.`,
      ["Uses official domain structure", "Includes trusted study paths", "Uses your selected study books", "Includes scenario application"],
      ["Needs active recall to lock in vocabulary", "Needs checkpoint completion to prove retention"],
      "Use the flashcards, then pass the checkpoints before moving to the next drill.",
    ),
    cisspReview: reviewPanel(
      79,
      "Bridge and leadership aware",
      "The bridge framing is explicit and the strategic lens keeps the lesson useful beyond the exam, but you still need to practice expressing tradeoffs out loud.",
      ["Connects to higher-level domains", "Encourages tradeoff thinking", "Introduces leadership prompts"],
      ["Needs more enterprise framing in your own words", "Needs repeated scenario practice"],
      "After each SSCP answer, add one sentence about governance, business risk, architecture impact, or stakeholder communication.",
    ),
    missedConcepts: ["passive recall", "tradeoff framing", "leadership translation"],
  };
}

function buildFallbackQuestion(
  domainId: SscpDomainId,
  questionDomainIds: SscpDomainId[],
  index: number,
  format: QuestionFormat,
  notes: ImportedNoteChunk[] = [],
  thinkingLevel: ThinkingLevel = "sscp",
  options: QuestionBuildOptions,
): QuestionBlueprint {
  const domain = getSscpDomain(domainId);
  const partnerDomain = questionDomainIds[1] ? getSscpDomain(questionDomainIds[1]) : null;
  const objective = domain.objectives[(index + options.objectiveOffset) % domain.objectives.length];
  const matchingNotes = notes.filter((note) => note.domainId === domainId);
  const noteAnchor = matchingNotes[(index + options.noteOffset) % Math.max(1, matchingNotes.length)];
  const trustedResources = getTrustedResources(domainId);
  const trustedAnchor = trustedResources[(index + options.trustedOffset) % Math.max(1, trustedResources.length)];
  const scenarioSeed = buildExamScenarioSeed(domain, partnerDomain, options.variantIndex + index);
  const objectiveCue = buildObjectiveCue(objective);
  const citations = sortCitations([
    domain.officialCitation,
    ...(trustedAnchor?.citations ?? []),
    ...(noteAnchor ? [noteCitation(noteAnchor)] : []),
  ]);
  const sourceTypes = [...new Set(citations.map((citation) => citation.trustLevel))];
  const strategicTakeaway = partnerDomain
    ? `If this issue spans ${domain.title.toLowerCase()} and ${partnerDomain.title.toLowerCase()} repeatedly, what would a senior security leader standardize, measure, or escalate?`
    : `If this topic showed up repeatedly, what would a senior security leader standardize, measure, or escalate?`;
  const scenarioContext = scenarioSeed.context;
  const answerLenses = buildAnswerLenses(questionDomainIds, objective.title, strategicTakeaway, noteAnchor);

  if (format === "single_select") {
    const options = [
      { id: "a", label: "A", text: scenarioSeed.bestAction },
      { id: "b", label: "B", text: scenarioSeed.distractorOne },
      { id: "c", label: "C", text: scenarioSeed.distractorTwo },
      { id: "d", label: "D", text: scenarioSeed.distractorThree },
    ];
    const optionRationales: OptionRationale[] = [
      {
        optionId: "a",
        rationale: "This is best because it applies the correct control response directly, reduces immediate risk, and creates evidence for follow-up.",
      },
      {
        optionId: "b",
        rationale: "This distractor delays or weakens the immediate control response instead of fixing the active problem.",
      },
      {
        optionId: "c",
        rationale: "This distractor sacrifices control quality, accountability, or security discipline for convenience.",
      },
      {
        optionId: "d",
        rationale: "This distractor avoids the correct operational response or ignores the need for evidence-based handling.",
      },
    ];
    return {
      id: `${domainId}-${index}-single`,
      format,
      title: formatQuestionTitle(index, format),
      prompt: `${scenarioSeed.stem} ${objectiveCue} Which of the following actions should the security team take?`,
      domainIds: questionDomainIds,
      objectiveIds: [objective.id],
      difficulty: thinkingLevel === "sscp" ? "foundation" : thinkingLevel === "cissp" ? "pressure" : "bridge",
      difficultyLabel: thinkingLevel === "sscp" ? "Best-answer practice" : thinkingLevel === "cissp" ? "Cross-domain pressure" : "Executive-risk pressure",
      scenarioContext,
      options,
      correctOptionIds: ["a"],
      optionRationales,
      idealAnswer: `Option A is best because ${scenarioSeed.bestActionReason}.`,
      answerGuidance: [
        `Anchor your reasoning to the objective "${objective.title}".`,
        questionDomainIds.length > 1
          ? `Show how ${partnerDomain?.title.toLowerCase()} changes or reinforces the control decision.`
          : "Keep the answer operational and direct.",
        "Explain why the best answer reduces risk more directly than the distractors.",
      ],
      answerKeyPhrases: objective.keywords,
      strategicTakeaway,
      answerLenses,
      citations,
      sourceTypes,
    };
  }

  if (format === "multi_select") {
    const options = [
      { id: "a", label: "A", text: scenarioSeed.bestAction },
      { id: "b", label: "B", text: scenarioSeed.secondAction },
      { id: "c", label: "C", text: scenarioSeed.distractorOne },
      { id: "d", label: "D", text: scenarioSeed.distractorTwo },
    ];
    return {
      id: `${domainId}-${index}-multi`,
      format,
      title: formatQuestionTitle(index, format),
      prompt: `${scenarioSeed.stem} ${objectiveCue} Which of the following actions should the security team take?`,
      domainIds: questionDomainIds,
      objectiveIds: [objective.id],
      difficulty: "pressure",
      difficultyLabel: thinkingLevel === "cto" ? "Leadership tradeoff check" : "Layered-control check",
      scenarioContext,
      options,
      correctOptionIds: ["a", "b"],
      optionRationales: [
        { optionId: "a", rationale: "This is a correct first move because it addresses the immediate control weakness directly." },
        { optionId: "b", rationale: "This is also correct because it strengthens evidence, validation, or follow-through after the initial control action." },
        { optionId: "c", rationale: "This distractor delays or weakens the needed response." },
        { optionId: "d", rationale: "This distractor keeps risk active or chooses convenience over disciplined control handling." },
      ],
      idealAnswer: `The best answers are A and B because the first action reduces the immediate risk and the second action makes the response defensible, measurable, and repeatable.`,
      answerGuidance: [
        `Choose the options that best support the objective "${objective.title}".`,
        questionDomainIds.length > 1
          ? `Be ready to explain how the second domain changes the control priorities.`
          : "Be ready to explain why the wrong options fail.",
      ],
      answerKeyPhrases: objective.keywords,
      strategicTakeaway,
      answerLenses,
      citations,
      sourceTypes,
    };
  }

  if (format === "scenario") {
    const options = [
      {
        id: "a",
        label: "A",
        text: scenarioSeed.bestAction,
      },
      {
        id: "b",
        label: "B",
        text: scenarioSeed.distractorOne,
      },
      {
        id: "c",
        label: "C",
        text: scenarioSeed.distractorTwo,
      },
      {
        id: "d",
        label: "D",
        text: scenarioSeed.distractorThree,
      },
    ];
    return {
      id: `${domainId}-${index}-scenario`,
      format,
      title: formatQuestionTitle(index, format),
      prompt: `${scenarioSeed.stem} ${objectiveCue} Which of the following actions should the security team take?`,
      domainIds: questionDomainIds,
      objectiveIds: [objective.id],
      difficulty: "bridge",
      difficultyLabel: thinkingLevel === "cto" ? "Executive-risk scenario" : "Scenario decision",
      scenarioContext,
      options,
      correctOptionIds: ["a"],
      optionRationales: [
        {
          optionId: "a",
          rationale: "This is the strongest exam answer because it applies the needed control now and still leaves room for broader improvement afterward.",
        },
        {
          optionId: "b",
          rationale: "Convenience-first responses are common distractors because they weaken accountability and leave risk active.",
        },
        {
          optionId: "c",
          rationale: "This distractor avoids the correct direct response and relies on deflection instead of action.",
        },
        {
          optionId: "d",
          rationale: "This distractor is too slow because the question asks for the best next action under active risk.",
        },
      ],
      idealAnswer: `Option A is best because ${scenarioSeed.bestActionReason}.`,
      answerGuidance: [
        "Start with the best next action, not with a long discussion.",
        questionDomainIds.length > 1
          ? `Show how ${partnerDomain?.title.toLowerCase()} affects the scenario and changes the tradeoff.`
          : "Show the direct control logic clearly.",
        "Explain why the correct option beats the distractors.",
        "Then compare the SSCP, CISSP, and CTO answer lenses underneath.",
      ],
      answerKeyPhrases: objective.keywords,
      strategicTakeaway,
      answerLenses,
      citations,
      sourceTypes,
    };
  }

  return {
    id: `${domainId}-${index}-short`,
    format: "short_answer",
    title: formatQuestionTitle(index, format),
    prompt: `${scenarioSeed.stem} ${objectiveCue} In 3-5 sentences, explain the best first response and why it is the strongest choice.`,
    domainIds: questionDomainIds,
    objectiveIds: [objective.id],
    difficulty: "pressure",
    difficultyLabel: thinkingLevel === "cto" ? "Strategic written response" : "Concise written response",
    scenarioContext,
    idealAnswer: `A strong answer identifies the immediate control action, explains why it reduces the active risk, and states what follow-up evidence, governance, or validation step should happen next.`,
    answerGuidance: [
      `Name the control goal behind the objective "${objective.title}".`,
      questionDomainIds.length > 1
        ? `Explain how ${partnerDomain?.title.toLowerCase()} changes the situation or the priority of the response.`
        : "Describe the operational action clearly.",
      "Describe the operational action.",
      "Mention one risk if the control is ignored.",
    ],
    answerKeyPhrases: objective.keywords,
    strategicTakeaway,
    answerLenses,
    citations,
    sourceTypes,
  };
}

export function buildFallbackDrill(request: DrillRequest, notes: ImportedNoteChunk[] = []): DrillResponse {
  const baseFormats: QuestionFormat[] =
    request.mode === "multiple_choice"
      ? ["single_select", "multi_select"]
    : request.mode === "short_answer"
        ? ["short_answer"]
      : request.mode === "scenario"
          ? ["scenario"]
          : ["single_select", "multi_select"];
  const generationSeed = normalizeSeed((request.generationNonce ?? Date.now()) + hashText(request.topicHint));
  const objectiveOffset = generationSeed % 11;
  const noteOffset = Math.floor(generationSeed / 7) % 13;
  const trustedOffset = Math.floor(generationSeed / 13) % 17;
  const partnerSalt = Math.floor(generationSeed / 17) % 19;
  const variantOffset = Math.floor(generationSeed / 19) % 23;
  const formats = rotateArray(baseFormats, generationSeed % baseFormats.length);
  const rotatedDomains = rotateArray(request.domainIds, Math.floor(generationSeed / 5) % request.domainIds.length);

  const questions = Array.from({ length: request.count }).map((_, index) => {
    const domainId = rotatedDomains[index % rotatedDomains.length];
    const format = formats[index % formats.length];
    const questionDomainIds = blendDomains(
      domainId,
      request.domainIds,
      request.domainMode ?? "combined",
      index,
      partnerSalt,
    );
    return buildFallbackQuestion(
      domainId,
      questionDomainIds,
      index,
      format,
      notes,
      request.thinkingLevel ?? "sscp",
      {
        objectiveOffset,
        noteOffset,
        trustedOffset,
        variantIndex: variantOffset,
      },
    );
  });
  const citations = sortCitations(questions.flatMap((question) => question.citations));

  return {
    generatedAt: new Date().toISOString(),
    questions,
    citations,
    sourceTypes: [...new Set(citations.map((citation) => citation.trustLevel))],
    confidenceLevel: inferConfidenceLevel(citations),
    sscpReview: reviewPanel(
      80,
      "SSCP drill ready",
      "These questions now lean toward certification-style stems, distractors, and best-answer logic instead of open discussion prompts.",
      ["Covers mapped domain objectives", "Uses trusted and PDF study anchors", "Blends question formats"],
      ["Needs live evaluation after answering"],
      "Answer every item with a confidence score so the tutor can pressure the right weak spots.",
    ),
    cisspReview: reviewPanel(
      69,
      "Bridge-capable",
      "The drill can already support higher-order reasoning, but the stronger CISSP value appears in the post-answer review.",
      ["Includes scenario prompts", "Invites cross-domain thinking"],
      ["Needs explicit tradeoff analysis in user answers"],
      "When you answer, always add one sentence about broader risk, governance, or architecture impact.",
    ),
    missedConcepts: ["tradeoff explanation", "confidence discipline"],
    recommendedNextTask:
      "Complete the drill, then submit at least one scenario answer for dual SSCP/CISSP evaluation.",
    selectedLevel: request.thinkingLevel ?? "sscp",
    domainMode: request.domainMode ?? "combined",
  };
}

export function buildFallbackResources(
  domainIds: SscpDomainId[],
  notes: ImportedNoteChunk[] = [],
  topicHint?: string,
): LearningResource[] {
  return domainIds.flatMap((domainId) => getFocusResources(domainId, notes, topicHint)).slice(0, 8);
}

export function sourcePolicyList(): Array<{ key: string; description: string }> {
  return Object.entries(SOURCE_POLICY).map(([key, description]) => ({ key, description }));
}
