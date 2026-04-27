import fs from "fs/promises";
import path from "path";
import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";
import type { SchemaEntity } from "@/app/utils/normalizeSchema";
import type {
  ScriptAudit,
  ScriptRuleCategory,
  ScriptRuleSeverity,
  ValidationReport,
  ValidationSummary,
  ValidatorIssue,
} from "@/app/XML-Validator/types";
import {
  attachAuditorReferences,
  buildValidatorPolicyContext,
} from "@/lib/xml-validator/policy";
import { parsePsModuleManifest } from "@/lib/ps-manifest";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const OPENAI_API_KEY = process.env.OPENAI_API_KEY!;
const OPENAI_BASE_URL = process.env.OPENAI_BASE_URL;
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";

const SYSTEM_PROMPT = `You are a senior One Identity Manager PowerShell connector validator.

You are the validation engine itself, not a post-processing reviewer.

Your job is to validate a connector XML file against the related PowerShell script using the supplied validation rules markdown as your rule prompt.

Important behavior:
- Always perform the validation with AI. Do not assume any deterministic pre-validation has happened.
- Analyze the PowerShell deeply before judging return bindings, command mappings, or method usage.
- Treat XML predefined commands as valid only when they correspond to PowerShell functions that are actually present in the uploaded script.
- When the uploaded PowerShell file is a .psd1 module manifest, treat FunctionsToExport as the public command allowlist that XML may use, even if the manifest does not contain the function bodies.
- In manifest mode, only treat global functions or commands explicitly listed in FunctionsToExport as public connector commands. Do not treat helper or private module functions as callable XML commands.
- For ReturnBindings and Bind checks, infer properties returned by the relevant PowerShell function even when the script uses loops, pipelines, Select-Object, helper functions, arrays of PSCustomObject, or other non-trivial construction patterns.
- For class read behavior, determine whether a ListingCommand really looks list-returning and whether an Item command really looks single-object-returning, even when that behavior is indirect.
- Treat an item-read definition as valid when an Item command appears either directly inside ReadConfiguration or inside ReadConfiguration > CommandSequence.
- If Item and ListingCommand use the same command, only treat that as valid when the PowerShell shows a believable branch, parameter-driven path, or filtering path that returns a single object for item reads.
- Treat item-read behavior as valid when the script narrows by a unique key or equivalent identifier and effectively returns zero-or-one matching objects, even if the PowerShell still emits that result as a one-item array/list or pipeline collection rather than a scalar object.
- When XML maps an item-read parameter from a unique key property and the shared command filters on that same parameter, prefer treating the same-command ListingCommand and Item pattern as valid unless the script clearly allows many matches for item reads.
- Check return bindings in the context of the same class and verify that the class's ListingCommand and Item command are actually represented by return bindings for that class.
- When a class uses the same command for both ListingCommand and Item, the same class-level ReturnBindings that reference that shared command satisfy both listing and item binding coverage. Do not require duplicated or distinct binding blocks just to represent both read modes.
- In each class, treat ReturnBinding as valid only when it uses that same class's ListingCommand or Item command from ReadConfiguration.
- In CommandMappings, require each Map Parameter value to match a real parameter on the corresponding referenced PowerShell function.
- In each class, require commands used in ModifiedBy to also appear in that same class's MethodConfiguration, typically in Insert or Update.
- For XML properties, treat the only valid DataType values as String, Int, Bool, and DateTime.
- Check that XML custom commands wrap their PowerShell body in a CDATA section rather than plain XML text.
- Inspect EnvironmentInitialization heuristically: the first step should usually import the PowerShell module, and the next step should usually be a connect/authentication command that prepares access to the target system.
- To find the connect/authentication step, inspect EnvironmentInitialization together with CustomCommands and the uploaded PowerShell script, and consider commands that establish sessions, tokens, headers, or global variables for the target system.
- When the initialization sequence is explicit, expect the first command to use Order="1" and the next connect/authentication step to use Order="2".
- For SetParameter validation, treat the only valid Source values as FixedValue, ConnectionParameter, GlobalVariable, SwitchParameter, and FixedArray.
- When SetParameter uses Source=ConnectionParameter, require its Value attribute to exactly match an existing XML ConnectionParameter Name.
- Inspect XML ConnectionParameter entries and, when the Name or Description clearly suggests a password, token, key, secret, or similar sensitive credential, expect IsSensibleData="true".
- Inspect the XML and the PowerShell for hardcoded secrets such as passwords, client secrets, API keys, tokens, private keys, and connection strings with embedded credentials.
- Inspect comments too, including XML comments, PowerShell comments, and disabled or example blocks that may still expose real sensitive values.
- Perform a PowerShell script audit focused on security and performance, and report concrete violated rules with evidence and a specific fix for each one.
- Use any internal SSCP study or tutor policy addendum only as reasoning support. Do not emit SSCP citations directly in the output.
- When external references are relevant to a PowerShell finding, rely only on the approved auditor source model and technology context supplied in the prompt.
- Never invent a CVE identifier. Prefer advisory-search guidance unless the prompt includes explicit CVE evidence.
- In the PowerShell audit, also check for meaningful logging, try/catch coverage around risky operations, and proper failure escalation with throw.
- In the PowerShell audit, check for SQL injection, LDAP injection, unsafe remote filter construction, insecure HTTP/cloud request construction, and TLS or certificate-validation weaknesses.
- In the PowerShell audit, also evaluate maintainability and clean-code patterns: enough useful comments, understandable naming, manageable function size, and structure that is easy to change or extend.
- Treat clean-code and maintainability findings as warnings by default and return practical tips or suggestions for improvement.
- Treat direct concatenation or interpolation of untrusted input into SQL, LDAP filters, URLs, query strings, headers, or request bodies as a likely security issue unless there is strong evidence of safe validation or escaping.
- For each PowerShell rule violation, return category, severity, scoreImpact, evidence, and fix text. Higher severity should deduct more from the script score.
- Use scoreImpact as points deducted from a base score of 100. Good defaults are low=4, medium=8, high=15, critical=25 unless the evidence strongly justifies a different impact.
- Distinguish likely real secrets from obvious placeholders or dummy examples; when uncertain, prefer a warning over an error and explain why.
- When a rule is clearly satisfied, do not emit an issue.
- When evidence is mixed or incomplete, prefer a warning over an error and make the uncertainty clear in the message.
- If only a module manifest is available and the root module/script body is not provided, do not raise parameter-signature, return-shape, or deep implementation errors solely because the manifest lacks function bodies. Call out that those checks are limited by missing module source.
- Use the rule codes defined in the rules prompt when they fit. If no existing rule code fits, use an "ai." prefixed code.
- Always return valid JSON matching the provided schema.
- For XML issues, line numbers must be 1-based and should point to the XML line that best represents the issue.
- For PowerShell audit violations, include the PowerShell line number when you can identify it confidently.
- "snippet" should be a short exact fragment from the XML line when possible so the UI can highlight it.
- "relatedPath" should be a short XML path or tag hint, for example <Bind CommandResultOf="Get-Data"> or <Map ToCommand="Create-User">.
- "analysis" should be a concise human-readable summary of the most important findings and assumptions.`;

const RESPONSE_SCHEMA = {
  name: "xml_validation_report",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["summary", "issues", "analysis", "scriptAudit"],
    properties: {
      analysis: { type: "string" },
      scriptAudit: {
        type: "object",
        additionalProperties: false,
        required: ["summary", "violatedRules"],
        properties: {
          summary: { type: "string" },
          violatedRules: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: [
                "code",
                "title",
                "category",
                "severity",
                "scoreImpact",
                "evidence",
                "fix",
                "line",
              ],
              properties: {
                code: { type: "string" },
                title: { type: "string" },
                category: {
                  type: "string",
                  enum: ["security", "performance", "quality"],
                },
                severity: {
                  type: "string",
                  enum: ["critical", "high", "medium", "low"],
                },
                scoreImpact: { type: "integer", minimum: 1, maximum: 100 },
                evidence: { type: "string" },
                fix: { type: "string" },
                line: {
                  anyOf: [{ type: "integer", minimum: 1 }, { type: "null" }],
                },
              },
            },
          },
        },
      },
      summary: {
        type: "object",
        additionalProperties: false,
        required: [
          "totalFunctions",
          "globalFunctions",
          "helperFunctions",
          "xmlClasses",
          "customCommands",
          "predefinedCommands",
          "inferredConnectionParameters",
          "actualConnectionParameters",
          "expectedEntities",
        ],
        properties: {
          totalFunctions: { type: "integer", minimum: 0 },
          globalFunctions: { type: "array", items: { type: "string" } },
          helperFunctions: { type: "array", items: { type: "string" } },
          xmlClasses: { type: "array", items: { type: "string" } },
          customCommands: { type: "array", items: { type: "string" } },
          predefinedCommands: { type: "array", items: { type: "string" } },
          inferredConnectionParameters: { type: "array", items: { type: "string" } },
          actualConnectionParameters: { type: "array", items: { type: "string" } },
          expectedEntities: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              required: ["entity", "operations", "hasClass"],
              properties: {
                entity: { type: "string" },
                operations: {
                  type: "array",
                  items: {
                    type: "string",
                    enum: ["List", "Insert", "Update", "Delete"],
                  },
                },
                hasClass: { type: "boolean" },
              },
            },
          },
        },
      },
      issues: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["code", "severity", "message", "line", "snippet", "relatedPath"],
          properties: {
            code: { type: "string" },
            severity: { type: "string", enum: ["error", "warning", "info"] },
            message: { type: "string" },
            line: { type: "integer", minimum: 1 },
            snippet: { type: "string" },
            relatedPath: { type: "string" },
          },
        },
      },
    },
  },
} as const;

const SCRIPT_SCORE_BY_SEVERITY: Record<ScriptRuleSeverity, number> = {
  critical: 25,
  high: 15,
  medium: 8,
  low: 4,
};

function bad(message: string, status = 400) {
  return NextResponse.json({ ok: false, error: message }, { status });
}

function truncate(label: string, value: string, limit = 22000) {
  const text = String(value || "").trim();
  if (!text) return `${label}:\n<empty>`;
  if (text.length <= limit) return `${label}:\n${text}`;
  return `${label}:\n${text.slice(0, limit)}\n\n[truncated ${text.length - limit} chars]`;
}

async function readRulesPrompt() {
  const rulesPath = path.join(process.cwd(), "doc", "xml-validator-rules.md");
  return fs.readFile(rulesPath, "utf8");
}

function clampLine(line: number, xmlLines: string[]) {
  if (!Number.isFinite(line)) return 1;
  return Math.max(1, Math.min(xmlLines.length || 1, Math.round(line)));
}

function parseSchemaEntities(schemaText: string): SchemaEntity[] {
  if (!schemaText.trim()) return [];

  try {
    const parsed = JSON.parse(schemaText);
    return Array.isArray(parsed) ? (parsed as SchemaEntity[]) : [];
  } catch {
    return [];
  }
}

type UploadedPsFile = {
  name: string;
  text: string;
};

type RawIssue = {
  code: string;
  severity: ValidatorIssue["severity"];
  message: string;
  line: number;
  snippet: string;
  relatedPath: string;
};

type ParsedPowerShellFunction = {
  name: string;
  isGlobal: boolean;
  parameters: Set<string>;
};

type ValidationEvidence = {
  publicCommands: Set<string>;
  xmlCustomCommands: Set<string>;
  functionParameters: Map<string, Set<string>>;
};

function normalizePowerShellFiles(body: {
  psText?: string;
  psFileName?: string;
  psFiles?: Array<{ name?: string; text?: string }>;
}) {
  const files = Array.isArray(body.psFiles)
    ? body.psFiles
        .map((file, index) => ({
          name: String(file?.name || `powershell-${index + 1}.txt`).trim(),
          text: String(file?.text || ""),
        }))
        .filter((file) => file.name && file.text.trim())
    : [];

  if (files.length > 0) return files;

  const psText = String(body.psText || "");
  if (!psText.trim()) return [];

  return [
    {
      name: String(body.psFileName || "powershell.txt").trim() || "powershell.txt",
      text: psText,
    },
  ];
}

function summarizePowerShellFiles(files: UploadedPsFile[]) {
  if (files.length === 0) return "";
  if (files.length === 1) return files[0].name;
  return `${files.length} files: ${files.map((file) => file.name).join(", ")}`;
}

function buildCombinedPowerShellText(files: UploadedPsFile[]) {
  return files
    .map((file) => `# File: ${file.name}\n${file.text}`)
    .join("\n\n");
}

function parseNamedEntriesFromXml(xmlText: string, tagName: string) {
  const names = new Set<string>();
  const expression = new RegExp(`<${tagName}\\b[^>]*\\bName="([^"]+)"`, "gi");

  for (const match of xmlText.matchAll(expression)) {
    const name = match[1]?.trim();
    if (name) {
      names.add(name.toLowerCase());
    }
  }

  return names;
}

function findMatchingParen(text: string, openParenIndex: number) {
  let depth = 0;

  for (let index = openParenIndex; index < text.length; index += 1) {
    const char = text[index];
    if (char === "(") depth += 1;
    if (char === ")") {
      depth -= 1;
      if (depth === 0) return index;
    }
  }

  return -1;
}

function parsePowerShellFunctions(files: UploadedPsFile[]) {
  const functions = new Map<string, ParsedPowerShellFunction>();

  for (const file of files) {
    if (!/\.(ps1|psm1)$/i.test(file.name)) continue;

    const matches = [...file.text.matchAll(/function\s+(global:)?([A-Za-z_][\w-]*)\s*\{/gi)];
    for (let index = 0; index < matches.length; index += 1) {
      const match = matches[index];
      const name = String(match[2] || "").trim();
      if (!name) continue;

      const regionStart = match.index ?? 0;
      const regionEnd = matches[index + 1]?.index ?? file.text.length;
      const region = file.text.slice(regionStart, regionEnd);
      const paramStart = region.search(/\bparam\s*\(/i);
      const parameters = new Set<string>();

      if (paramStart >= 0) {
        const openParenIndex = region.indexOf("(", paramStart);
        const closeParenIndex =
          openParenIndex >= 0 ? findMatchingParen(region, openParenIndex) : -1;
        const paramBlock =
          openParenIndex >= 0 && closeParenIndex > openParenIndex
            ? region.slice(openParenIndex + 1, closeParenIndex)
            : "";

        for (const paramMatch of paramBlock.matchAll(
          /(?:^|[\r\n,])\s*(?:\[[^\]]+\]\s*)*\$([A-Za-z_][\w]*)/gm
        )) {
          const paramName = paramMatch[1]?.trim();
          if (paramName) {
            parameters.add(paramName.toLowerCase());
          }
        }
      }

      functions.set(name.toLowerCase(), {
        name,
        isGlobal: Boolean(match[1]),
        parameters,
      });
    }
  }

  return functions;
}

function buildValidationEvidence(xmlText: string, files: UploadedPsFile[]): ValidationEvidence {
  const functions = parsePowerShellFunctions(files);
  const functionParameters = new Map<string, Set<string>>();
  const publicCommands = new Set<string>();
  const xmlCustomCommands = parseNamedEntriesFromXml(xmlText, "CustomCommand");
  const manifestFile = files.find((file) => /\.psd1$/i.test(file.name));
  const manifest = manifestFile ? parsePsModuleManifest(manifestFile.text) : null;

  for (const [functionName, details] of functions.entries()) {
    functionParameters.set(functionName, details.parameters);
  }

  if (manifest) {
    if (manifest.wildcardFunctionsToExport || manifest.functionsToExport.length === 0) {
      for (const functionName of functions.keys()) {
        publicCommands.add(functionName);
      }
    } else {
      for (const functionName of manifest.functionsToExport) {
        publicCommands.add(functionName.toLowerCase());
      }
    }

    for (const details of functions.values()) {
      if (details.isGlobal) {
        publicCommands.add(details.name.toLowerCase());
      }
    }
  } else {
    for (const functionName of functions.keys()) {
      publicCommands.add(functionName);
    }
  }

  return {
    publicCommands,
    xmlCustomCommands,
    functionParameters,
  };
}

function findXmlClassLine(xmlText: string, className: string) {
  const xmlLines = xmlText.split(/\r?\n/);
  const escapedClassName = className.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const classPattern = new RegExp(`<Class\\b[^>]*\\bName="${escapedClassName}"`);

  for (let index = 0; index < xmlLines.length; index += 1) {
    if (classPattern.test(xmlLines[index])) {
      return index + 1;
    }
  }

  return undefined;
}

function buildAnalysisNote(removedFalsePositives: number, groupedListingIssues: number) {
  const parts: string[] = [];

  if (removedFalsePositives > 0) {
    parts.push(
      `Post-processing removed ${removedFalsePositives} command or parameter finding${
        removedFalsePositives === 1 ? "" : "s"
      } that were contradicted by the uploaded PowerShell or XML.`
    );
  }

  if (groupedListingIssues > 0) {
    parts.push(
      `Post-processing grouped ${groupedListingIssues} repeated listing-binding finding${
        groupedListingIssues === 1 ? "" : "s"
      } into class-level warning summaries.`
    );
  }

  return parts.join(" ");
}

function sanitizeIssues(rawIssues: RawIssue[], xmlText: string, evidence: ValidationEvidence) {
  const retained: RawIssue[] = [];
  const listingCoverageGroups = new Map<
    string,
    {
      className: string;
      listingCommand: string;
      properties: string[];
      issues: RawIssue[];
    }
  >();
  let removedFalsePositives = 0;

  for (const issue of rawIssues) {
    if (issue.code === "map.parameter.missing") {
      const match = issue.message.match(/Map Parameter '([^']+)'.*function '([^']+)'/i);
      const parameterName = match?.[1]?.toLowerCase();
      const functionName = match?.[2]?.toLowerCase();
      const functionParameters = functionName
        ? evidence.functionParameters.get(functionName)
        : undefined;

      if (parameterName && functionParameters?.has(parameterName)) {
        removedFalsePositives += 1;
        continue;
      }
    }

    if (issue.code === "xml.predefined.missing-global" || issue.code === "xml.command.missing") {
      const match = issue.message.match(/'([^']+)'/);
      const commandName = match?.[1]?.toLowerCase();
      if (
        commandName &&
        (evidence.publicCommands.has(commandName) || evidence.xmlCustomCommands.has(commandName))
      ) {
        removedFalsePositives += 1;
        continue;
      }
    }

    if (issue.code === "xml.class.returnbind.listing-command.missing") {
      const match = issue.message.match(
        /^([^']+?) property '([^']+)'.*listing command '([^']+)'/i
      );
      const className = match?.[1]?.trim();
      const propertyName = match?.[2]?.trim();
      const listingCommand = match?.[3]?.trim();

      if (className && propertyName && listingCommand) {
        const groupKey = `${className.toLowerCase()}::${listingCommand.toLowerCase()}`;
        const existingGroup = listingCoverageGroups.get(groupKey) || {
          className,
          listingCommand,
          properties: [],
          issues: [],
        };

        existingGroup.properties.push(propertyName);
        existingGroup.issues.push(issue);
        listingCoverageGroups.set(groupKey, existingGroup);
        continue;
      }
    }

    retained.push(issue);
  }

  let groupedListingIssues = 0;
  for (const group of listingCoverageGroups.values()) {
    if (group.issues.length === 1) {
      retained.push(group.issues[0]);
      continue;
    }

    groupedListingIssues += group.issues.length;
    const uniqueProperties = [...new Set(group.properties)];
    const sampleProperties = uniqueProperties.slice(0, 6).join(", ");
    const remainingCount = uniqueProperties.length - Math.min(uniqueProperties.length, 6);
    const classLine = findXmlClassLine(xmlText, group.className);

    retained.push({
      code: "xml.class.returnbind.listing-command.missing",
      severity: "warning",
      message: `${group.className} has ${uniqueProperties.length} properties that only bind to item-read results and are not exposed by the listing command '${group.listingCommand}'. This usually means the list command returns a partial object shape. Properties: ${sampleProperties}${
        remainingCount > 0 ? ` (+${remainingCount} more)` : ""
      }.`,
      line: classLine ?? Math.min(...group.issues.map((item) => item.line)),
      snippet: `<Class Name="${group.className}">`,
      relatedPath: `<Class Name="${group.className}">`,
    });
  }

  return {
    issues: retained,
    analysisNote: buildAnalysisNote(removedFalsePositives, groupedListingIssues),
  };
}

function buildManifestPromptFromFiles(files: UploadedPsFile[]) {
  const manifestFile = files.find((file) => /\.psd1$/i.test(file.name));
  if (!manifestFile) return "";

  const manifest = parsePsModuleManifest(manifestFile.text);
  const exportsLabel =
    manifest.functionsToExport.length > 0
      ? manifest.functionsToExport.join(", ")
      : manifest.wildcardFunctionsToExport
        ? "*"
        : "<none declared>";
  const hasRootModuleSource =
    !!manifest.rootModule &&
    files.some((file) => file.name.toLowerCase() === manifest.rootModule?.toLowerCase());

  return [
    "PowerShell manifest context:",
    `- Manifest file: ${manifestFile.name}`,
    "- The uploaded PowerShell files include a module manifest (.psd1).",
    `- RootModule: ${manifest.rootModule || "<not declared>"}`,
    `- FunctionsToExport: ${exportsLabel}`,
    hasRootModuleSource
      ? `- Matching root module source was also uploaded: ${manifest.rootModule}`
      : "- Matching root module source was not uploaded, so deep function-body checks may be limited.",
    "- Validation rule: XML may use commands listed in FunctionsToExport even when the manifest itself does not contain the PowerShell function bodies.",
    "- Validation rule: do not treat helper/private functions as public XML commands unless they are global or exported by the manifest.",
    "- Validation rule: if the root module body is not present in the upload, limit parameter-signature and deep implementation findings accordingly.",
  ].join("\n");
}

function locateSnippet(lineText: string, snippet: string) {
  const trimmed = snippet.trim();
  if (!trimmed) return { column: undefined, length: undefined };

  const index = lineText.indexOf(trimmed);
  if (index >= 0) {
    return { column: index + 1, length: trimmed.length };
  }

  return { column: undefined, length: undefined };
}

function normalizeSummary(summary: ValidationSummary): ValidationSummary {
  return {
    totalFunctions: Number(summary.totalFunctions || 0),
    globalFunctions: Array.isArray(summary.globalFunctions) ? summary.globalFunctions : [],
    helperFunctions: Array.isArray(summary.helperFunctions) ? summary.helperFunctions : [],
    xmlClasses: Array.isArray(summary.xmlClasses) ? summary.xmlClasses : [],
    customCommands: Array.isArray(summary.customCommands) ? summary.customCommands : [],
    predefinedCommands: Array.isArray(summary.predefinedCommands) ? summary.predefinedCommands : [],
    inferredConnectionParameters: Array.isArray(summary.inferredConnectionParameters)
      ? summary.inferredConnectionParameters
      : [],
    actualConnectionParameters: Array.isArray(summary.actualConnectionParameters)
      ? summary.actualConnectionParameters
      : [],
    expectedEntities: Array.isArray(summary.expectedEntities) ? summary.expectedEntities : [],
  };
}

function normalizeScriptSeverity(value: unknown): ScriptRuleSeverity {
  if (value === "critical" || value === "high" || value === "medium" || value === "low") {
    return value;
  }

  return "medium";
}

function normalizeScriptCategory(value: unknown): ScriptRuleCategory {
  if (value === "security" || value === "performance" || value === "quality") {
    return value;
  }

  return "quality";
}

function normalizeScriptAudit(rawAudit: {
  summary?: string;
  violatedRules?: Array<{
    code?: string;
    title?: string;
    category?: ScriptRuleCategory;
    severity?: ScriptRuleSeverity;
    scoreImpact?: number;
    evidence?: string;
    fix?: string;
    line?: number;
  }>;
}): ScriptAudit {
  const violatedRules = Array.isArray(rawAudit?.violatedRules)
    ? rawAudit.violatedRules.map((violation, index) => {
        const severity = normalizeScriptSeverity(violation?.severity);
        const scoreImpact = Number.isFinite(violation?.scoreImpact)
          ? Math.max(1, Math.min(100, Math.round(Number(violation.scoreImpact))))
          : SCRIPT_SCORE_BY_SEVERITY[severity];
        const line = Number.isFinite(violation?.line)
          ? Math.max(1, Math.round(Number(violation?.line)))
          : undefined;

        return {
          id: `${String(violation?.code || "ps.rule")}-${index}-${Math.random()
            .toString(36)
            .slice(2, 8)}`,
          code: String(violation?.code || "ps.quality.generic"),
          title: String(violation?.title || "PowerShell rule violation"),
          category: normalizeScriptCategory(violation?.category),
          severity,
          scoreImpact,
          evidence: String(violation?.evidence || "").trim(),
          fix: String(violation?.fix || "").trim(),
          ...(line ? { line } : {}),
        };
      })
    : [];

  violatedRules.sort((left, right) => right.scoreImpact - left.scoreImpact);

  const totalScore = Math.max(
    0,
    Math.min(
      100,
      100 - violatedRules.reduce((sum, violation) => sum + violation.scoreImpact, 0)
    )
  );

  return {
    totalScore,
    summary: String(rawAudit?.summary || "").trim(),
    violatedRules,
  };
}

function normalizeIssues(rawIssues: RawIssue[], xmlText: string): ValidatorIssue[] {
  const xmlLines = xmlText.split(/\r?\n/);

  return rawIssues.map((issue) => {
    const line = clampLine(issue.line, xmlLines);
    const lineText = xmlLines[line - 1] || "";
    const { column, length } = locateSnippet(lineText, issue.snippet);

    return {
      id: `${issue.code}-${line}-${Math.random().toString(36).slice(2, 8)}`,
      code: issue.code,
      severity: issue.severity,
      message: issue.message,
      line,
      column,
      length,
      relatedPath: issue.relatedPath || undefined,
    };
  });
}

export async function POST(req: NextRequest) {
  if (!OPENAI_API_KEY) return bad("server missing OPENAI_API_KEY", 500);

  let body: {
    xmlText?: string;
    psText?: string;
    psFileName?: string;
    psFiles?: Array<{ name?: string; text?: string }>;
    schemaText?: string;
  };

  try {
    body = await req.json();
  } catch {
    return bad("invalid JSON body");
  }

  const xmlText = String(body.xmlText || "");
  const psFiles = normalizePowerShellFiles(body);
  const psText = buildCombinedPowerShellText(psFiles);
  const psFileName = summarizePowerShellFiles(psFiles);
  const schemaText = String(body.schemaText || "");

  if (!xmlText.trim()) return bad("missing xmlText");
  if (!psText.trim()) return bad("missing psText");

  const rulesPrompt = await readRulesPrompt();
  const schemaEntities = parseSchemaEntities(schemaText);
  const policyContext = await buildValidatorPolicyContext(xmlText, psText);
  const manifestPrompt = buildManifestPromptFromFiles(psFiles);
  const validationEvidence = buildValidationEvidence(xmlText, psFiles);

  const openai = new OpenAI({
    apiKey: OPENAI_API_KEY,
    ...(OPENAI_BASE_URL ? { baseURL: OPENAI_BASE_URL } : {}),
  });

  const userPrompt = [
    "Validate this XML/PowerShell pair using the supplied rules prompt.",
    "",
    truncate("Validation rules prompt", rulesPrompt, 22000),
    "",
    truncate("Internal policy addendum", policyContext.promptAddendum, 12000),
    "",
    manifestPrompt ? truncate("Manifest interpretation", manifestPrompt, 6000) : "",
    manifestPrompt ? "" : "",
    truncate("Connector XML", xmlText, 24000),
    "",
    ...psFiles.flatMap((file) => [
      truncate(`PowerShell file (${file.name})`, file.text, 18000),
      "",
    ]),
    "",
    truncate("Schema JSON", JSON.stringify(schemaEntities, null, 2), 8000),
  ]
    .filter(Boolean)
    .join("\n");

  try {
    const completion = await openai.chat.completions.create({
      model: OPENAI_MODEL,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userPrompt },
      ],
      temperature: 0,
      response_format: {
        type: "json_schema",
        json_schema: RESPONSE_SCHEMA,
      },
    });

    const content = completion.choices[0]?.message?.content?.trim() || "";
    if (!content) {
      throw new Error("AI validator returned empty content");
    }

    const parsed = JSON.parse(content) as {
      summary: ValidationSummary;
      issues: RawIssue[];
      analysis: string;
      scriptAudit: {
        summary: string;
        violatedRules: Array<{
          code: string;
          title: string;
          category: ScriptRuleCategory;
          severity: ScriptRuleSeverity;
          scoreImpact: number;
          evidence: string;
          fix: string;
          line?: number;
        }>;
      };
    };

    const sanitized = sanitizeIssues(parsed.issues || [], xmlText, validationEvidence);
    const analysis = String(parsed.analysis || "").trim();
    const normalizedAnalysis = sanitized.analysisNote
      ? [analysis, sanitized.analysisNote].filter(Boolean).join("\n\n")
      : analysis;

    const report: ValidationReport = {
      summary: normalizeSummary(parsed.summary),
      issues: normalizeIssues(sanitized.issues, xmlText),
      analysis: normalizedAnalysis,
      scriptAudit: {
        ...(await (async () => {
          const normalizedAudit = normalizeScriptAudit(parsed.scriptAudit || {});
          return {
            ...normalizedAudit,
            violatedRules: await attachAuditorReferences(
              normalizedAudit.violatedRules,
              policyContext
            ),
          };
        })()),
      },
      derivedSchema: schemaEntities,
    };

    return NextResponse.json({ ok: true, report });
  } catch (error: any) {
    return bad(error?.message || "AI validation failed", 502);
  }
}
