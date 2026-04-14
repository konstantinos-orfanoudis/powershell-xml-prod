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

function normalizeIssues(
  rawIssues: Array<{
    code: string;
    severity: ValidatorIssue["severity"];
    message: string;
    line: number;
    snippet: string;
    relatedPath: string;
  }>,
  xmlText: string
): ValidatorIssue[] {
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
    schemaText?: string;
  };

  try {
    body = await req.json();
  } catch {
    return bad("invalid JSON body");
  }

  const xmlText = String(body.xmlText || "");
  const psText = String(body.psText || "");
  const schemaText = String(body.schemaText || "");

  if (!xmlText.trim()) return bad("missing xmlText");
  if (!psText.trim()) return bad("missing psText");

  const rulesPrompt = await readRulesPrompt();
  const schemaEntities = parseSchemaEntities(schemaText);
  const policyContext = await buildValidatorPolicyContext(xmlText, psText);

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
    truncate("Connector XML", xmlText, 24000),
    "",
    truncate("PowerShell file", psText, 24000),
    "",
    truncate("Schema JSON", JSON.stringify(schemaEntities, null, 2), 8000),
  ].join("\n");

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
      issues: Array<{
        code: string;
        severity: ValidatorIssue["severity"];
        message: string;
        line: number;
        snippet: string;
        relatedPath: string;
      }>;
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

    const report: ValidationReport = {
      summary: normalizeSummary(parsed.summary),
      issues: normalizeIssues(parsed.issues || [], xmlText),
      analysis: String(parsed.analysis || "").trim(),
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
