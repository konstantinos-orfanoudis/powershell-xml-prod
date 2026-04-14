import fs from "node:fs/promises";
import path from "node:path";

import type {
  ScriptRuleReference,
  ScriptRuleReferenceConfidence,
  ScriptRuleViolation,
} from "@/app/XML-Validator/types";
import { CURATED_RESOURCES, SSCP_DOMAINS } from "@/lib/sscp/catalog";
import { loadCachedImportedNotes } from "@/lib/sscp/notes";
import type { ImportedNoteChunk, SscpDomainId } from "@/lib/sscp/types";

type AuditorSourceRecord = {
  id: string;
  family: string;
  title: string;
  authority: string;
  url: string;
  applies_to?: string[];
};

type AuditorRuleRecord = {
  id: string;
  title: string;
  category: string;
  severity: string;
  source_ids?: string[];
};

type AuditorSourcesPayload = {
  sources?: AuditorSourceRecord[];
  rule_mapping?: Record<string, string[]>;
};

type AuditorRulesPayload = {
  rules?: AuditorRuleRecord[];
};

type VendorHint = {
  id: string;
  label: string;
  patterns: RegExp[];
  hostPatterns: RegExp[];
  modulePatterns: RegExp[];
  advisoryTitle: string;
  advisoryUrl: string;
};

export interface InferredTechnology {
  id: string;
  label: string;
  confidence: ScriptRuleReferenceConfidence;
  versions: string[];
  hosts: string[];
  modules: string[];
  evidence: string[];
}

export interface ValidatorPolicyContext {
  promptAddendum: string;
  technologies: InferredTechnology[];
  allowedReferences: ScriptRuleReference[];
}

type NormalizedAuditorCatalog = {
  sourcesById: Map<string, AuditorSourceRecord>;
  rulesById: Map<string, AuditorRuleRecord>;
  ruleMapping: Record<string, string[]>;
};

const AUDITOR_ASSET_DIR = path.join(
  process.cwd(),
  "dist",
  "oneim-vbnet-auditor-apiserver-work",
  "assets"
);

const SSCP_TARGET_DOMAINS: SscpDomainId[] = [
  "security-concepts-practices",
  "risk-identification-monitoring-analysis",
  "incident-response-recovery",
  "cryptography",
  "network-communications-security",
  "systems-application-security",
];

const VENDOR_HINTS: VendorHint[] = [
  {
    id: "microsoft",
    label: "Microsoft / Azure / Graph",
    patterns: [/\bmicrosoft\b/i, /\bazure\b/i, /\bgraph\b/i, /\bentra\b/i],
    hostPatterns: [/microsoft\.com/i, /graph\.microsoft/i, /login\.microsoftonline/i],
    modulePatterns: [/microsoft/i, /\baz\b/i, /graph/i],
    advisoryTitle: "Microsoft Security Response Center",
    advisoryUrl: "https://msrc.microsoft.com/update-guide/",
  },
  {
    id: "okta",
    label: "Okta",
    patterns: [/\bokta\b/i],
    hostPatterns: [/okta\.com/i, /oktapreview\.com/i],
    modulePatterns: [/okta/i],
    advisoryTitle: "Okta Security Advisories",
    advisoryUrl: "https://trust.okta.com/security-advisories/",
  },
  {
    id: "sap",
    label: "SAP",
    patterns: [/\bsap\b/i, /\bs4\b/i],
    hostPatterns: [/sap\.com/i],
    modulePatterns: [/sap/i],
    advisoryTitle: "SAP Security Notes and News",
    advisoryUrl: "https://support.sap.com/en/my-support/knowledge-base/security-notes-news.html",
  },
  {
    id: "oneidentity",
    label: "One Identity",
    patterns: [/\bone identity\b/i, /\boneim\b/i],
    hostPatterns: [/oneidentity\.com/i],
    modulePatterns: [/oneidentity/i],
    advisoryTitle: "One Identity Security Notices",
    advisoryUrl: "https://support.oneidentity.com/product-notification/notices",
  },
  {
    id: "aws",
    label: "Amazon Web Services",
    patterns: [/\baws\b/i, /\bamazon web services\b/i],
    hostPatterns: [/amazonaws\.com/i, /\.aws\./i],
    modulePatterns: [/\baws/i],
    advisoryTitle: "AWS Security Bulletins",
    advisoryUrl: "https://aws.amazon.com/security/security-bulletins/",
  },
  {
    id: "salesforce",
    label: "Salesforce",
    patterns: [/\bsalesforce\b/i],
    hostPatterns: [/salesforce\.com/i, /force\.com/i],
    modulePatterns: [/salesforce/i],
    advisoryTitle: "Salesforce Security Advisories",
    advisoryUrl: "https://help.salesforce.com/s/articleView?id=sf.security_advisories.htm&type=5",
  },
  {
    id: "vmware",
    label: "VMware",
    patterns: [/\bvmware\b/i],
    hostPatterns: [/vmware\.com/i, /broadcom\.com/i],
    modulePatterns: [/vmware/i],
    advisoryTitle: "VMware / Broadcom Security Advisories",
    advisoryUrl: "https://support.broadcom.com/group/ecx/security-advisories",
  },
  {
    id: "github",
    label: "GitHub",
    patterns: [/\bgithub\b/i],
    hostPatterns: [/github\.com/i],
    modulePatterns: [/github/i],
    advisoryTitle: "GitHub Security Advisories",
    advisoryUrl: "https://github.com/advisories",
  },
];

const SOURCE_HINTS: Array<{
  tokens: RegExp[];
  sourceIds: string[];
  mappingKeys?: string[];
}> = [
  {
    tokens: [/\bsql\b/i, /\bdatabase\b/i, /\bquery\b/i, /\bconnection string\b/i],
    sourceIds: ["ca2100", "owasp-sql-injection", "dotnet-connection-strings"],
    mappingKeys: ["sql-and-db-access"],
  },
  {
    tokens: [/\bldap\b/i, /\bdirectory\b/i, /\bfilter\b/i],
    sourceIds: ["owasp-ldap-injection"],
  },
  {
    tokens: [/\bhttp\b/i, /\bhttps\b/i, /\bweb request\b/i, /\buri\b/i, /\burl\b/i],
    sourceIds: ["httpclient-guidelines", "syslib0014", "owasp-ssrf"],
    mappingKeys: ["web-requests"],
  },
  {
    tokens: [/\btls\b/i, /\bssl\b/i, /\bcertificate\b/i, /\bprotocol\b/i],
    sourceIds: ["ca5359", "ca5364"],
    mappingKeys: ["web-requests"],
  },
  {
    tokens: [/\bsecret\b/i, /\bpassword\b/i, /\btoken\b/i, /\bapi key\b/i, /\bcredential\b/i],
    sourceIds: ["owasp-credential-storage", "dotnet-connection-strings"],
  },
  {
    tokens: [/\bxml\b/i, /\bxxe\b/i, /\bdeserialize\b/i, /\bdtd\b/i],
    sourceIds: ["ca3075", "owasp-xxe", "ca2300", "ca2310"],
    mappingKeys: ["xml-and-deserialization"],
  },
  {
    tokens: [/\bpath\b/i, /\bfile\b/i, /\bwrite\b/i, /\bread\b/i, /\bupload\b/i],
    sourceIds: ["ca3003", "owasp-path-traversal", "owasp-file-upload"],
    mappingKeys: ["file-reading-and-writing"],
  },
  {
    tokens: [/\bprocess\b/i, /\bstart-process\b/i, /\binvoke-expression\b/i, /\bcmd\.exe\b/i],
    sourceIds: ["owasp-command-injection", "vb-security"],
    mappingKeys: ["process-execution"],
  },
  {
    tokens: [/\bcatch\b/i, /\bthrow\b/i, /\blog\b/i, /\bexception\b/i],
    sourceIds: ["ca1031", "ca2200", "oneim-system-debugger-context"],
    mappingKeys: ["reliability-with-security-impact"],
  },
  {
    tokens: [/\bperformance\b/i, /\bloop\b/i, /\bcount\b/i, /\benumerat/i, /\bstringbuilder\b/i],
    sourceIds: ["ca1827", "ca1851", "stringbuilder-guidance"],
    mappingKeys: ["performance"],
  },
];

let auditorCatalogPromise: Promise<NormalizedAuditorCatalog> | null = null;

function uniqueStrings(items: Iterable<string>) {
  return [...new Set(Array.from(items).filter(Boolean))];
}

function stripBom(text: string) {
  return text.replace(/^\uFEFF/, "");
}

function normalizeAscii(text: string) {
  return text.replace(/[^\x09\x0A\x0D\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
}

function scoreNeedle(haystack: string, needle: string) {
  if (!needle) return 0;
  return haystack.includes(needle) ? Math.max(1, needle.length) : 0;
}

function scoreDomainContext(haystack: string, domainId: SscpDomainId) {
  const domain = SSCP_DOMAINS.find((entry) => entry.id === domainId);
  if (!domain) return 0;

  const terms = uniqueStrings([
    domain.title,
    domain.summary,
    ...domain.glossary,
    ...domain.objectives.flatMap((objective) => [
      objective.title,
      objective.summary,
      ...objective.keywords,
    ]),
  ])
    .map((item) => item.toLowerCase())
    .filter((item) => item.length >= 4);

  return terms.reduce((score, term) => score + scoreNeedle(haystack, term), 0);
}

function scoreNoteContext(haystack: string, note: ImportedNoteChunk) {
  const terms = uniqueStrings([
    note.title,
    note.excerpt,
    ...(note.keywords ?? []),
    note.sectionLabel,
  ])
    .join(" ")
    .toLowerCase()
    .split(/[^a-z0-9]+/i)
    .filter((term) => term.length >= 5);

  return terms.reduce((score, term) => score + scoreNeedle(haystack, term), 0);
}

function parseModuleImports(text: string) {
  const matches = [...text.matchAll(/Import-Module\s+([^\r\n]+)/gi)];

  return uniqueStrings(
    matches
      .map((match) => match[1] || "")
      .map((segment) => segment.trim())
      .map((segment) =>
        segment
          .split(/\s+-/)[0]
          ?.trim()
          .replace(/^['"]|['"]$/g, "")
      )
      .map((segment) => path.basename(segment || "", path.extname(segment || "")))
      .filter(Boolean)
  );
}

function parseHosts(text: string) {
  return uniqueStrings(
    [...text.matchAll(/https?:\/\/([a-z0-9._:-]+)/gi)]
      .map((match) => (match[1] || "").toLowerCase())
      .filter(Boolean)
  );
}

function parseVersions(text: string) {
  return uniqueStrings(
    [...text.matchAll(/\b\d+\.\d+(?:\.\d+){0,2}\b/g)]
      .map((match) => match[0])
      .filter(Boolean)
  );
}

function inferConfidence(evidenceCount: number, hasVersion: boolean): ScriptRuleReferenceConfidence {
  if (evidenceCount >= 3 || (evidenceCount >= 2 && hasVersion)) return "high";
  if (evidenceCount >= 2) return "medium";
  return "low";
}

function buildSearchReference(
  id: string,
  title: string,
  authority: string,
  url: string,
  confidence: ScriptRuleReferenceConfidence
): ScriptRuleReference {
  return { id, title, authority, url, kind: "advisory-search", confidence };
}

function buildVendorReferences(technology: InferredTechnology) {
  const hint = VENDOR_HINTS.find((entry) => entry.id === technology.id);
  if (!hint) return [] as ScriptRuleReference[];

  return [
    buildSearchReference(
      `${technology.id}-vendor-advisories`,
      hint.advisoryTitle,
      hint.label,
      hint.advisoryUrl,
      technology.confidence
    ),
  ];
}

function buildNvdAndCisaReferences(technology: InferredTechnology) {
  const versionSuffix = technology.versions[0] ? ` ${technology.versions[0]}` : "";
  const query = `${technology.label}${versionSuffix}`.trim();
  const encoded = encodeURIComponent(query);

  return [
    buildSearchReference(
      `${technology.id}-nvd-vuln-search`,
      `NVD vulnerability search for ${query}`,
      "NVD",
      `https://nvd.nist.gov/vuln/search/results?form_type=Basic&results_type=overview&query=${encoded}&search_type=all`,
      technology.confidence
    ),
    buildSearchReference(
      `${technology.id}-nvd-cpe-search`,
      `NVD product / CPE search for ${query}`,
      "NVD",
      `https://nvd.nist.gov/products/cpe/search/results?namingFormat=2.3&keyword=${encoded}`,
      technology.confidence
    ),
    buildSearchReference(
      `${technology.id}-cisa-kev-search`,
      `CISA KEV search for ${query}`,
      "CISA",
      `https://www.cisa.gov/known-exploited-vulnerabilities-catalog?search_api_fulltext=${encoded}`,
      technology.confidence === "low" ? "medium" : technology.confidence
    ),
  ];
}

function extractInlineCves(text: string): ScriptRuleReference[] {
  return uniqueStrings(
    [...text.matchAll(/\bCVE-\d{4}-\d{4,7}\b/gi)].map((match) => match[0].toUpperCase())
  ).map((cve) => ({
    id: cve.toLowerCase(),
    title: `${cve} (inline reference from upload)`,
    authority: "NVD",
    url: `https://nvd.nist.gov/vuln/detail/${encodeURIComponent(cve)}`,
    kind: "cve",
    confidence: "high",
  }));
}

export function inferPowerShellTechnologies(xmlText: string, psText: string): InferredTechnology[] {
  const combined = `${xmlText}\n${psText}`;
  const normalized = combined.toLowerCase();
  const modules = parseModuleImports(combined);
  const hosts = parseHosts(combined);
  const versions = parseVersions(combined);

  return VENDOR_HINTS.map((hint) => {
    const evidence = new Set<string>();
    const matchedModules = modules.filter((moduleName) =>
      hint.modulePatterns.some((pattern) => pattern.test(moduleName))
    );
    const matchedHosts = hosts.filter((host) =>
      hint.hostPatterns.some((pattern) => pattern.test(host))
    );

    if (hint.patterns.some((pattern) => pattern.test(normalized))) {
      evidence.add(`Matched product keywords for ${hint.label}.`);
    }
    if (matchedModules.length > 0) {
      evidence.add(`Matched module imports: ${matchedModules.join(", ")}.`);
    }
    if (matchedHosts.length > 0) {
      evidence.add(`Matched endpoint hosts: ${matchedHosts.join(", ")}.`);
    }

    if (evidence.size === 0) return null;

    const localVersions = uniqueStrings(
      versions.filter((version) => combined.toLowerCase().includes(version.toLowerCase()))
    ).slice(0, 3);

    return {
      id: hint.id,
      label: hint.label,
      confidence: inferConfidence(evidence.size, localVersions.length > 0),
      versions: localVersions,
      hosts: matchedHosts.slice(0, 4),
      modules: matchedModules.slice(0, 4),
      evidence: [...evidence],
    } satisfies InferredTechnology;
  }).filter((entry): entry is InferredTechnology => Boolean(entry));
}

async function loadAuditorCatalog(): Promise<NormalizedAuditorCatalog> {
  if (!auditorCatalogPromise) {
    auditorCatalogPromise = (async () => {
      const [sourcesRaw, rulesRaw] = await Promise.all([
        fs.readFile(path.join(AUDITOR_ASSET_DIR, "approved-sources.json"), "utf8"),
        fs.readFile(path.join(AUDITOR_ASSET_DIR, "audit-rules.json"), "utf8"),
      ]);

      const sourcesPayload = JSON.parse(stripBom(sourcesRaw)) as AuditorSourcesPayload;
      const rulesPayload = JSON.parse(stripBom(rulesRaw)) as AuditorRulesPayload;
      const sources = sourcesPayload.sources ?? [];
      const rules = rulesPayload.rules ?? [];

      return {
        sourcesById: new Map(sources.map((source) => [source.id, source])),
        rulesById: new Map(rules.map((rule) => [rule.id, rule])),
        ruleMapping: sourcesPayload.rule_mapping ?? {},
      };
    })();
  }

  return auditorCatalogPromise;
}

function toPolicyReference(
  source: AuditorSourceRecord,
  confidence: ScriptRuleReferenceConfidence
): ScriptRuleReference {
  return {
    id: source.id,
    title: source.title,
    authority: source.authority,
    url: source.url,
    kind: "policy",
    confidence,
  };
}

function dedupeReferences(references: ScriptRuleReference[]) {
  const seen = new Set<string>();
  return references.filter((reference) => {
    if (seen.has(reference.id)) return false;
    seen.add(reference.id);
    return true;
  });
}

function describeTechnology(technology: InferredTechnology) {
  const details = [
    technology.versions.length > 0 ? `versions: ${technology.versions.join(", ")}` : null,
    technology.modules.length > 0 ? `modules: ${technology.modules.join(", ")}` : null,
    technology.hosts.length > 0 ? `hosts: ${technology.hosts.join(", ")}` : null,
  ]
    .filter(Boolean)
    .join("; ");

  return `- ${technology.label} (${technology.confidence} confidence)${details ? ` - ${details}` : ""}`;
}

function buildSscpPromptAddendum(
  haystack: string,
  notes: ImportedNoteChunk[]
): string {
  const domainScores = SSCP_TARGET_DOMAINS.map((domainId) => ({
    domainId,
    score: scoreDomainContext(haystack, domainId),
  }))
    .sort((left, right) => right.score - left.score)
    .slice(0, 4);

  const domainLines = domainScores.map(({ domainId }) => {
    const domain = SSCP_DOMAINS.find((entry) => entry.id === domainId);
    if (!domain) return null;

    const objective = domain.objectives[0];
    return `- ${domain.title}: ${normalizeAscii(domain.summary)} Key lens: ${normalizeAscii(objective?.summary || domain.summary)}`;
  });

  const noteLines = notes
    .map((note) => ({
      note,
      score: scoreNoteContext(haystack, note),
    }))
    .sort((left, right) => right.score - left.score)
    .slice(0, 3)
    .map(({ note }) => `- ${note.fileName} / ${note.sectionLabel}: ${normalizeAscii(note.excerpt).slice(0, 260)}`);

  const resourceLines = CURATED_RESOURCES.filter((resource) =>
    domainScores.some(({ domainId }) => resource.domainIds.includes(domainId))
  )
    .slice(0, 3)
    .map((resource) => `- ${resource.sourceName}: ${resource.title} - ${normalizeAscii(resource.sscpFit)}`);

  return [
    "Internal SSCP policy addendum for PowerShell connector review:",
    "- Use these as internal reasoning lenses only. Do not expose SSCP or study-source citations in the user-facing findings unless they directly strengthen a visible security recommendation.",
    "- Prioritize least privilege, secure defaults, transport security, secret handling, monitoring, incident readiness, and change-safe maintainability.",
    ...domainLines.filter(Boolean),
    ...(resourceLines.length > 0 ? ["Trusted study-resource anchors:", ...resourceLines] : []),
    ...(noteLines.length > 0 ? ["Local tutor note anchors:", ...noteLines] : []),
  ].join("\n");
}

function buildAuditorPromptAddendum(
  catalog: NormalizedAuditorCatalog,
  technologies: InferredTechnology[],
  inlineCves: ScriptRuleReference[]
) {
  const mappedSourceIds = uniqueStrings(
    Object.values(catalog.ruleMapping).flat().filter(Boolean)
  ).slice(0, 18);

  const sourceLines = mappedSourceIds
    .map((sourceId) => catalog.sourcesById.get(sourceId))
    .filter((source): source is AuditorSourceRecord => Boolean(source))
    .map(
      (source) =>
        `- [${source.id}] ${source.title} (${source.authority}) - ${source.url}`
    );

  const technologyLines =
    technologies.length > 0
      ? technologies.map(describeTechnology)
      : ["- No clear vendor or product signature was inferred from the upload."];

  const inlineCveLines =
    inlineCves.length > 0
      ? inlineCves.map((reference) => `- [${reference.id}] ${reference.title} - ${reference.url}`)
      : ["- No explicit CVE identifiers were found inside the uploaded XML or PowerShell."];

  return [
    "Auditor-approved external reference model for PowerShell findings:",
    "- Use approved Microsoft Learn and OWASP policy references where they fit the finding.",
    "- Use NVD, NVD product/CPE search, CISA KEV, and relevant vendor advisory pages for best-effort PowerShell-related advisory context.",
    "- Never invent a CVE identifier. Emit a concrete cve reference only when a literal CVE is already present in the upload or when the provided context explicitly includes it.",
    "- When product/version evidence is incomplete, prefer advisory-search references over concrete cve references.",
    "Relevant approved policy sources:",
    ...sourceLines,
    "Inferred connector technologies:",
    ...technologyLines,
    "Inline CVE evidence from the upload:",
    ...inlineCveLines,
  ].join("\n");
}

function collectAllowedReferences(
  catalog: NormalizedAuditorCatalog,
  technologies: InferredTechnology[],
  inlineCves: ScriptRuleReference[]
) {
  const mappedPolicyReferences = uniqueStrings(
    Object.values(catalog.ruleMapping).flat().filter(Boolean)
  )
    .map((sourceId) => catalog.sourcesById.get(sourceId))
    .filter((source): source is AuditorSourceRecord => Boolean(source))
    .map((source) => toPolicyReference(source, "medium"));

  const technologyReferences = technologies.flatMap((technology) => [
    ...buildVendorReferences(technology),
    ...buildNvdAndCisaReferences(technology),
  ]);

  return dedupeReferences([
    ...mappedPolicyReferences,
    ...technologyReferences,
    ...inlineCves,
  ]);
}

export async function buildValidatorPolicyContext(
  xmlText: string,
  psText: string
): Promise<ValidatorPolicyContext> {
  const [catalog, notes] = await Promise.all([
    loadAuditorCatalog(),
    loadCachedImportedNotes().catch(() => [] as ImportedNoteChunk[]),
  ]);

  const combined = `${xmlText}\n${psText}`;
  const technologies = inferPowerShellTechnologies(xmlText, psText);
  const inlineCves = extractInlineCves(combined);
  const allowedReferences = collectAllowedReferences(catalog, technologies, inlineCves);

  const promptAddendum = [
    buildSscpPromptAddendum(combined.toLowerCase(), notes),
    "",
    buildAuditorPromptAddendum(catalog, technologies, inlineCves),
  ].join("\n");

  return {
    promptAddendum,
    technologies,
    allowedReferences,
  };
}

function getPolicySourceIdsForViolation(
  violation: ScriptRuleViolation,
  catalog: NormalizedAuditorCatalog
) {
  const haystack = `${violation.code} ${violation.title} ${violation.evidence} ${violation.fix}`.toLowerCase();
  const sourceIds = new Set<string>();

  for (const hint of SOURCE_HINTS) {
    if (hint.tokens.some((token) => token.test(haystack))) {
      for (const sourceId of hint.sourceIds) sourceIds.add(sourceId);
      for (const mappingKey of hint.mappingKeys ?? []) {
        for (const sourceId of catalog.ruleMapping[mappingKey] ?? []) {
          sourceIds.add(sourceId);
        }
      }
    }
  }

  if (violation.category === "performance") {
    for (const sourceId of catalog.ruleMapping.performance ?? []) {
      sourceIds.add(sourceId);
    }
  }

  if (violation.category === "quality") {
    for (const sourceId of catalog.ruleMapping["reliability-with-security-impact"] ?? []) {
      sourceIds.add(sourceId);
    }
  }

  const matchingRule = catalog.rulesById.get(violation.code);
  for (const sourceId of matchingRule?.source_ids ?? []) {
    sourceIds.add(sourceId);
  }

  return [...sourceIds];
}

function mapSeverityToConfidence(severity: ScriptRuleViolation["severity"]): ScriptRuleReferenceConfidence {
  if (severity === "critical" || severity === "high") return "high";
  if (severity === "medium") return "medium";
  return "low";
}

export async function attachAuditorReferences(
  violations: ScriptRuleViolation[],
  context: ValidatorPolicyContext
): Promise<ScriptRuleViolation[]> {
  if (violations.length === 0) return violations;

  const catalog = await loadAuditorCatalog();
  const allowedById = new Map(context.allowedReferences.map((reference) => [reference.id, reference]));

  return violations.map((violation) => {
    const confidence = mapSeverityToConfidence(violation.severity);
    const policyReferences = getPolicySourceIdsForViolation(violation, catalog)
      .map((sourceId) => catalog.sourcesById.get(sourceId))
      .filter((source): source is AuditorSourceRecord => Boolean(source))
      .map((source) => toPolicyReference(source, confidence));

    const advisoryReferences =
      violation.category === "security"
        ? context.allowedReferences.filter(
            (reference) =>
              reference.kind !== "policy" &&
              (context.technologies.length === 0 ||
                context.technologies.some((technology) => reference.id.startsWith(technology.id)))
          )
        : [];

    const inlineCveReferences =
      violation.category === "security"
        ? context.allowedReferences.filter((reference) => reference.kind === "cve")
        : [];

    const references = dedupeReferences([
      ...policyReferences.map((reference) => allowedById.get(reference.id) ?? reference),
      ...advisoryReferences,
      ...inlineCveReferences,
    ]).slice(0, 5);

    return references.length > 0 ? { ...violation, references } : violation;
  });
}
