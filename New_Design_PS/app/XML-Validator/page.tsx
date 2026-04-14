"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { SchemaEntity } from "../utils/normalizeSchema";
import type {
  ScriptRuleCategory,
  ScriptRuleReference,
  ScriptRuleSeverity,
  ValidationReport,
  ValidatorIssue,
} from "./types";

function severityTheme(severity: ValidatorIssue["severity"]) {
  if (severity === "error") {
    return {
      bubble: "border-rose-200 bg-rose-50 text-rose-800",
      dot: "bg-rose-500",
      inline: "bg-rose-200",
      row: "bg-rose-950/35",
      panel: "border-rose-200 bg-rose-50 text-rose-800",
    };
  }

  if (severity === "warning") {
    return {
      bubble: "border-amber-200 bg-amber-50 text-amber-800",
      dot: "bg-amber-500",
      inline: "bg-amber-200",
      row: "bg-amber-950/30",
      panel: "border-amber-200 bg-amber-50 text-amber-800",
    };
  }

  return {
    bubble: "border-sky-200 bg-sky-50 text-sky-800",
    dot: "bg-sky-500",
    inline: "bg-sky-200",
    row: "bg-sky-950/30",
    panel: "border-sky-200 bg-sky-50 text-sky-800",
  };
}

function splitHighlight(lineText: string, column?: number, length?: number) {
  if (!column || column < 1 || !length || length <= 0) {
    return { pre: lineText, mark: "", post: "" };
  }

  const start = Math.max(0, Math.min(lineText.length, column - 1));
  const end = Math.max(start, Math.min(lineText.length, start + length));

  return {
    pre: lineText.slice(0, start),
    mark: lineText.slice(start, end),
    post: lineText.slice(end),
  };
}

function readWorkspaceSchemaEntities() {
  try {
    const raw = localStorage.getItem("schema.entities");
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? (parsed as SchemaEntity[]) : [];
  } catch {
    return [];
  }
}

function formatSeverityLabel(severity: ValidatorIssue["severity"]) {
  if (severity === "error") return "Error";
  if (severity === "warning") return "Warning";
  return "Info";
}

const severityOrder: Array<ValidatorIssue["severity"]> = ["error", "warning", "info"];

function scriptRuleTheme(severity: ScriptRuleSeverity) {
  if (severity === "critical") {
    return {
      card: "border-rose-300 bg-rose-50 text-rose-900",
      badge: "bg-rose-600 text-white",
      dot: "bg-rose-600",
    };
  }

  if (severity === "high") {
    return {
      card: "border-orange-300 bg-orange-50 text-orange-900",
      badge: "bg-orange-500 text-white",
      dot: "bg-orange-500",
    };
  }

  if (severity === "medium") {
    return {
      card: "border-amber-300 bg-amber-50 text-amber-900",
      badge: "bg-amber-500 text-white",
      dot: "bg-amber-500",
    };
  }

  return {
    card: "border-sky-300 bg-sky-50 text-sky-900",
    badge: "bg-sky-500 text-white",
    dot: "bg-sky-500",
  };
}

function scriptScoreTheme(score: number) {
  if (score >= 85) {
    return {
      shell: "border-emerald-200 bg-emerald-50",
      text: "text-emerald-700",
      bar: "bg-emerald-500",
    };
  }

  if (score >= 70) {
    return {
      shell: "border-sky-200 bg-sky-50",
      text: "text-sky-700",
      bar: "bg-sky-500",
    };
  }

  if (score >= 50) {
    return {
      shell: "border-amber-200 bg-amber-50",
      text: "text-amber-700",
      bar: "bg-amber-500",
    };
  }

  return {
    shell: "border-rose-200 bg-rose-50",
    text: "text-rose-700",
    bar: "bg-rose-500",
  };
}

function formatScriptCategory(category: ScriptRuleCategory) {
  if (category === "security") return "Security";
  if (category === "performance") return "Performance";
  return "Quality";
}

function formatReferenceKind(kind: ScriptRuleReference["kind"]) {
  if (kind === "cve") return "CVE";
  if (kind === "advisory-search") return "Advisory Search";
  return "Policy";
}

function formatReferenceConfidence(confidence: ScriptRuleReference["confidence"]) {
  return confidence.charAt(0).toUpperCase() + confidence.slice(1);
}

type AnalysisSection = {
  title: string;
  body?: string;
  items?: string[];
};

function cleanAnalysisItem(line: string) {
  return line.replace(/^[-*]\s+/, "").replace(/^\d+\.\s+/, "").trim();
}

function parseAnalysisSections(analysis: string): AnalysisSection[] {
  const normalized = analysis.trim();
  if (!normalized) return [];

  const paragraphs = normalized
    .split(/\n\s*\n/)
    .map((part) => part.trim())
    .filter(Boolean);

  return paragraphs.map((paragraph, index) => {
    const lines = paragraph
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);

    const firstLine = lines[0] || "";
    const hasHeading = /:\s*$/.test(firstLine) && lines.length > 1;
    const title = hasHeading
      ? firstLine.replace(/:\s*$/, "")
      : index === 0
        ? "AI Summary"
        : `AI Note ${index + 1}`;
    const contentLines = hasHeading ? lines.slice(1) : lines;
    const firstBulletIndex = contentLines.findIndex(
      (line) => /^[-*]\s+/.test(line) || /^\d+\.\s+/.test(line)
    );

    if (firstBulletIndex === 0) {
      return {
        title,
        items: contentLines.map(cleanAnalysisItem).filter(Boolean),
      };
    }

    if (firstBulletIndex > 0) {
      return {
        title,
        body: contentLines.slice(0, firstBulletIndex).join(" "),
        items: contentLines.slice(firstBulletIndex).map(cleanAnalysisItem).filter(Boolean),
      };
    }

    return {
      title,
      body: contentLines.join(" "),
    };
  });
}

function UploadButton(props: {
  label: string;
  detail: string;
  accept: string;
  onUpload: (file: File) => Promise<void> | void;
}) {
  return (
    <label className="group flex min-h-[120px] cursor-pointer flex-col justify-between rounded-[1.75rem] border border-slate-200 bg-white px-5 py-4 shadow-sm transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md">
      <div>
        <div className="text-xs font-semibold uppercase tracking-[0.26em] text-sky-600">
          Upload
        </div>
        <div className="mt-3 text-lg font-semibold text-slate-900">{props.label}</div>
        <div className="mt-2 text-sm leading-6 text-slate-500">{props.detail}</div>
      </div>
      <div className="mt-4 inline-flex w-fit rounded-full border border-slate-300 px-3 py-1.5 text-xs font-medium text-slate-700 transition group-hover:border-slate-400 group-hover:bg-slate-50">
        Choose file
      </div>
      <input
        type="file"
        accept={props.accept}
        className="hidden"
        onChange={async (event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (!file) return;
          await props.onUpload(file);
        }}
      />
    </label>
  );
}

export default function XmlValidatorPage() {
  const [xmlText, setXmlText] = useState("");
  const [psText, setPsText] = useState("");
  const [xmlFileName, setXmlFileName] = useState("");
  const [psFileName, setPsFileName] = useState("");
  const [pageError, setPageError] = useState("");
  const [report, setReport] = useState<ValidationReport | null>(null);
  const [resultsOpen, setResultsOpen] = useState(false);
  const [validationBusy, setValidationBusy] = useState(false);
  const [focusedIssueId, setFocusedIssueId] = useState<string>("");
  const [activeSeverity, setActiveSeverity] = useState<ValidatorIssue["severity"]>("error");

  const lineRefs = useRef<Map<number, HTMLDivElement>>(new Map());

  useEffect(() => {
    if (!resultsOpen) return;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setResultsOpen(false);
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [resultsOpen]);

  useEffect(() => {
    if (!resultsOpen) return;

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, [resultsOpen]);

  const findings = report?.issues ?? [];
  const xmlLines = useMemo(() => (xmlText ? xmlText.split(/\r?\n/) : [""]), [xmlText]);

  const counts = useMemo(
    () =>
      findings.reduce(
        (acc, issue) => {
          acc[issue.severity] += 1;
          return acc;
        },
        { error: 0, warning: 0, info: 0 }
      ),
    [findings]
  );

  const issuesByLine = useMemo(() => {
    const map = new Map<number, ValidatorIssue[]>();

    for (const issue of findings) {
      const line = Math.max(1, Math.min(xmlLines.length || 1, issue.line || 1));
      const bucket = map.get(line) ?? [];
      bucket.push(issue);
      map.set(line, bucket);
    }

    return map;
  }, [findings, xmlLines.length]);

  const highlightedLineEntries = useMemo(
    () => Array.from(issuesByLine.entries()).sort(([left], [right]) => left - right),
    [issuesByLine]
  );
  const findingsBySeverity = useMemo(
    () =>
      severityOrder.reduce(
        (acc, severity) => {
          acc[severity] = findings
            .filter((issue) => issue.severity === severity)
            .sort((left, right) => left.line - right.line);
          return acc;
        },
        { error: [], warning: [], info: [] } as Record<
          ValidatorIssue["severity"],
          ValidatorIssue[]
        >
      ),
    [findings]
  );
  const activeFindings = findingsBySeverity[activeSeverity];
  const visibleLineEntries = useMemo(
    () =>
      highlightedLineEntries
        .map(([lineNumber, lineIssues]) => [
          lineNumber,
          lineIssues.filter((issue) => issue.severity === activeSeverity),
        ] as const)
        .filter((entry) => entry[1].length > 0),
    [activeSeverity, highlightedLineEntries]
  );

  const analysisSections = useMemo(
    () => parseAnalysisSections(report?.analysis || ""),
    [report?.analysis]
  );
  const scriptAuditSections = useMemo(
    () => parseAnalysisSections(report?.scriptAudit.summary || ""),
    [report?.scriptAudit.summary]
  );
  const scriptViolations = report?.scriptAudit.violatedRules ?? [];
  const scriptSeverityCounts = useMemo(
    () =>
      scriptViolations.reduce(
        (acc, rule) => {
          acc[rule.severity] += 1;
          return acc;
        },
        { critical: 0, high: 0, medium: 0, low: 0 }
      ),
    [scriptViolations]
  );

  async function loadXmlFile(file: File) {
    setXmlText(await file.text());
    setXmlFileName(file.name);
    setPageError("");
    setReport(null);
    setFocusedIssueId("");
    setActiveSeverity("error");
  }

  async function loadPsFile(file: File) {
    setPsText(await file.text());
    setPsFileName(file.name);
    setPageError("");
    setReport(null);
    setFocusedIssueId("");
    setActiveSeverity("error");
  }

  async function runValidation() {
    setPageError("");

    if (!xmlText.trim() || !psText.trim()) {
      setPageError("Upload both the connector XML and the PowerShell file before validating.");
      return null;
    }

    setValidationBusy(true);

    try {
      const response = await fetch("/api/ai/xml-validator", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          xmlText,
          psText,
          schemaText: JSON.stringify(readWorkspaceSchemaEntities(), null, 2),
        }),
      });

      const payload = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(payload?.error || `Validation failed (${response.status})`);
      }

      const nextReport = payload?.report as ValidationReport | undefined;
      if (!nextReport) {
        throw new Error("AI validator returned no report");
      }

      setReport(nextReport);
      const firstSeverityWithFindings =
        severityOrder.find((severity) =>
          nextReport.issues.some((issue) => issue.severity === severity)
        ) ?? "error";
      setActiveSeverity(firstSeverityWithFindings);
      setFocusedIssueId(
        nextReport.issues.find((issue) => issue.severity === firstSeverityWithFindings)?.id ?? ""
      );
      setResultsOpen(true);
      return nextReport;
    } catch (error) {
      setPageError((error as Error).message);
      return null;
    } finally {
      setValidationBusy(false);
    }
  }

  function exportReportHtml() {
    if (!report) return;

    const score = report.scriptAudit.totalScore ?? 0;
    const scoreColor = score >= 85 ? "#10b981" : score >= 70 ? "#0ea5e9" : score >= 50 ? "#f59e0b" : "#ef4444";
    const scoreShell = score >= 85 ? "#ecfdf5;border-color:#6ee7b7" : score >= 70 ? "#f0f9ff;border-color:#7dd3fc" : score >= 50 ? "#fffbeb;border-color:#fcd34d" : "#fff1f2;border-color:#fca5a5";

    function sev(s: string) {
      if (s === "error") return { dot: "#ef4444", bg: "#fff1f2", border: "#fca5a5", text: "#9f1239" };
      if (s === "warning") return { dot: "#f59e0b", bg: "#fffbeb", border: "#fcd34d", text: "#92400e" };
      return { dot: "#0ea5e9", bg: "#f0f9ff", border: "#7dd3fc", text: "#075985" };
    }

    function ruleSev(s: string) {
      if (s === "critical") return { bg: "#fff1f2", border: "#fca5a5", badge: "#dc2626" };
      if (s === "high") return { bg: "#fff7ed", border: "#fdba74", badge: "#f97316" };
      if (s === "medium") return { bg: "#fffbeb", border: "#fcd34d", badge: "#f59e0b" };
      return { bg: "#f8fafc", border: "#cbd5e1", badge: "#64748b" };
    }

    function e(s: string | null | undefined) {
      return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }

    function card(content: string, extra = "") {
      return `<div style="border-radius:1.25rem;border:1px solid #e2e8f0;background:#fff;padding:16px;margin-bottom:12px;${extra}">${content}</div>`;
    }

    function label(text: string) {
      return `<div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.2em;color:#94a3b8;margin-bottom:8px">${e(text)}</div>`;
    }

    const allIssues = report.issues ?? [];
    const errCount = allIssues.filter(i => i.severity === "error").length;
    const warnCount = allIssues.filter(i => i.severity === "warning").length;
    const infoCount = allIssues.filter(i => i.severity === "info").length;
    const violations = report.scriptAudit.violatedRules ?? [];
    const sum = report.summary;

    // Summary stats row
    const statsRow = [
      { label: "Errors", value: errCount, color: "#be123c" },
      { label: "Warnings", value: warnCount, color: "#92400e" },
      { label: "Info", value: infoCount, color: "#075985" },
      { label: "PS Score", value: `${score}/100`, color: scoreColor },
    ].map(st =>
      `<div style="flex:1;border-radius:1rem;border:1px solid #e2e8f0;background:#fff;padding:12px 14px">
        <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.2em;color:#94a3b8">${e(st.label)}</div>
        <div style="margin-top:6px;font-size:18px;font-weight:700;color:${st.color}">${e(String(st.value))}</div>
      </div>`
    ).join("");

    // Summary info card
    const summaryCard = sum ? card(`
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
        <div>${label("XML Classes")}<div style="font-weight:600;color:#0f172a">${sum.xmlClasses.length}</div></div>
        <div>${label("Global Functions")}<div style="font-weight:600;color:#0f172a">${sum.globalFunctions.length}</div></div>
      </div>
      ${sum.actualConnectionParameters.length > 0 ? `<p style="margin-top:10px;font-size:13px;color:#475569">Connection parameters: <strong>${e(sum.actualConnectionParameters.join(", "))}</strong></p>` : ""}
    `) : "";

    // PS score block
    const psScoreBlock = `
      <div style="border-radius:1.25rem;border:1px solid;background:${scoreShell.split(";")[0].split(":")[1]};border-color:${scoreShell.split(";")[1].split(":")[1]};padding:16px;margin-bottom:12px">
        <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px">
          <div>
            ${label("PowerShell Quality")}
            <div style="font-size:36px;font-weight:700;color:${scoreColor}">${score}<span style="font-size:14px;color:#64748b;font-weight:500">/100</span></div>
          </div>
          <div style="border-radius:999px;border:1px solid rgba(255,255,255,.7);background:rgba(255,255,255,.8);padding:4px 12px;font-size:11px;font-weight:600;color:#475569">${violations.length} violated rules</div>
        </div>
        <div style="margin-top:12px;height:8px;border-radius:999px;background:rgba(255,255,255,.8)">
          <div style="height:8px;border-radius:999px;background:${scoreColor};width:${score}%"></div>
        </div>
        <div style="margin-top:12px;display:flex;flex-wrap:wrap;gap:8px">
          ${["critical","high","medium","low"].map(sev2 => {
            const cnt = violations.filter(v => v.severity === sev2).length;
            return `<span style="border-radius:999px;border:1px solid rgba(255,255,255,.7);background:rgba(255,255,255,.8);padding:4px 12px;font-size:11px;color:#475569">${e(sev2.charAt(0).toUpperCase()+sev2.slice(1))}: ${cnt}</span>`;
          }).join("")}
        </div>
      </div>`;

    // Script audit sections
    const auditSections = parseAnalysisSections(report.scriptAudit.summary || "");
    const auditHtml = auditSections.length > 0 ? auditSections.map((section, idx) => {
      const isLead = idx === 0;
      const bg = isLead ? "#0f172a" : "#f8fafc";
      const border = isLead ? "#0f172a" : "#e2e8f0";
      const titleColor = isLead ? "#7dd3fc" : "#94a3b8";
      const bodyColor = isLead ? "#f1f5f9" : "#334155";
      return `<div style="border-radius:1.1rem;border:1px solid ${border};background:${bg};padding:14px;margin-bottom:10px">
        <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.2em;color:${titleColor}">${e(section.title)}</div>
        ${section.body ? `<p style="margin-top:8px;font-size:13px;line-height:1.6;color:${bodyColor}">${e(section.body)}</p>` : ""}
        ${section.items && section.items.length ? `<div style="margin-top:10px">${section.items.map((item, i) => `
          <div style="display:flex;align-items:flex-start;gap:10px;border-radius:1rem;padding:10px 12px;background:${isLead ? "rgba(255,255,255,.07)" : "#f1f5f9"};margin-bottom:6px">
            <span style="flex-shrink:0;width:22px;height:22px;border-radius:999px;background:${isLead ? "rgba(125,211,252,.2)" : "#e0f2fe"};color:${isLead ? "#bae6fd" : "#0369a1"};display:inline-flex;align-items:center;justify-content:center;font-size:11px;font-weight:700">${i+1}</span>
            <span style="font-size:13px;line-height:1.6;color:${bodyColor}">${e(item)}</span>
          </div>`).join("")}</div>` : ""}
      </div>`;
    }).join("") : "";

    // PS violations
    const violationsHtml = violations.length > 0 ? violations.map(rule => {
      const t = ruleSev(rule.severity);
      return `<div style="border-radius:1.25rem;border:1px solid ${t.border};background:${t.bg};padding:16px;margin-bottom:10px">
        <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:10px;flex-wrap:wrap">
          <div style="display:flex;gap:8px;flex-wrap:wrap">
            <span style="border-radius:999px;background:${t.badge};color:#fff;padding:4px 10px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.15em">${e(rule.severity)}</span>
            <span style="border-radius:999px;border:1px solid rgba(0,0,0,.1);background:rgba(255,255,255,.7);padding:4px 10px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.15em">${e(formatScriptCategory(rule.category))}</span>
          </div>
          <span style="border-radius:999px;border:1px solid rgba(0,0,0,.1);background:rgba(255,255,255,.7);padding:4px 12px;font-size:11px;font-weight:600">-${rule.scoreImpact} pts</span>
        </div>
        <h3 style="margin:10px 0 4px;font-size:13px;font-weight:700">${e(rule.title)}</h3>
        <div style="font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.15em;color:#64748b">${e(rule.code)}${rule.line ? ` · PS line ${rule.line}` : ""}</div>
        <p style="margin-top:10px;font-size:13px;line-height:1.6">${e(rule.evidence)}</p>
        <div style="margin-top:10px;border-radius:1rem;border:1px solid rgba(255,255,255,.8);background:rgba(255,255,255,.8);padding:12px">
          <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.17em;color:#94a3b8">Suggested Fix</div>
          <p style="margin-top:6px;font-size:13px;line-height:1.6;color:#334155">${e(rule.fix)}</p>
        </div>
        ${rule.references && rule.references.length > 0 ? `
        <div style="margin-top:10px;border-radius:1rem;border:1px solid rgba(255,255,255,.8);background:rgba(255,255,255,.8);padding:12px">
          <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.17em;color:#94a3b8">Related References</div>
          ${rule.references.map(ref => `
            <a href="${e(ref.url)}" target="_blank" rel="noreferrer" style="display:block;border-radius:1rem;border:1px solid #e2e8f0;background:#fff;padding:12px;margin-top:8px;text-decoration:none;color:inherit">
              <div style="display:flex;gap:6px;flex-wrap:wrap">
                <span style="border-radius:999px;border:1px solid #e2e8f0;background:#f8fafc;padding:3px 8px;font-size:10px;font-weight:700;text-transform:uppercase;color:#64748b">${e(formatReferenceKind(ref.kind))}</span>
                <span style="border-radius:999px;border:1px solid #e2e8f0;background:#f8fafc;padding:3px 8px;font-size:10px;font-weight:700;text-transform:uppercase;color:#64748b">${e(formatReferenceConfidence(ref.confidence))}</span>
              </div>
              <div style="margin-top:8px;font-size:13px;font-weight:700;color:#0f172a">${e(ref.title)}</div>
              <div style="margin-top:2px;font-size:11px;color:#64748b">${e(ref.authority)}</div>
              <div style="margin-top:6px;font-size:11px;color:#0369a1;word-break:break-all">${e(ref.url)}</div>
            </a>`).join("")}
        </div>` : ""}
      </div>`;
    }).join("") : `<div style="border-radius:1.25rem;border:1px solid #6ee7b7;background:#ecfdf5;padding:14px;font-size:13px;color:#065f46">No PowerShell security or performance rule violations were returned for this upload pair.</div>`;

    // XML findings
    const issueRows = (sev2: string) => {
      const t = sev(sev2);
      const list = allIssues.filter(i => i.severity === sev2).sort((a,b) => a.line - b.line);
      if (!list.length) return `<div style="border-radius:1.25rem;border:1px solid #e2e8f0;background:#f8fafc;padding:12px;font-size:13px;color:#475569">No ${sev2} messages.</div>`;
      return list.map(issue => `
        <div style="border-radius:1.25rem;border:1px solid ${t.border};background:${t.bg};padding:14px;margin-bottom:8px">
          <div style="display:flex;align-items:flex-start;gap:10px">
            <span style="margin-top:5px;flex-shrink:0;width:10px;height:10px;border-radius:999px;background:${t.dot};display:inline-block"></span>
            <div>
              <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.17em;color:${t.text}">
                ${e(sev2.charAt(0).toUpperCase()+sev2.slice(1))} · Line ${e(String(issue.line))}
              </div>
              <p style="margin-top:6px;font-size:13px;line-height:1.6;color:${t.text}">${e(issue.message)}</p>
              ${issue.code ? `<div style="margin-top:4px;font-size:10px;font-weight:600;color:#64748b">${e(issue.code)}</div>` : ""}
            </div>
          </div>
        </div>`).join("");
    };

    // AI Notes
    const aiSections = parseAnalysisSections(report.analysis || "");
    const aiHtml = aiSections.length > 0 ? aiSections.map((section, idx) => {
      const isLead = idx === 0;
      const bg = isLead ? "#0f172a" : "#f8fafc";
      const border = isLead ? "#0f172a" : "#e2e8f0";
      const titleColor = isLead ? "#7dd3fc" : "#94a3b8";
      const bodyColor = isLead ? "#f1f5f9" : "#334155";
      return `<div style="border-radius:1.1rem;border:1px solid ${border};background:${bg};padding:14px;margin-bottom:10px">
        <div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.2em;color:${titleColor}">${e(section.title)}</div>
        ${section.body ? `<p style="margin-top:8px;font-size:13px;line-height:1.6;color:${bodyColor}">${e(section.body)}</p>` : ""}
        ${section.items && section.items.length ? `<div style="margin-top:10px">${section.items.map((item, i) => `
          <div style="display:flex;align-items:flex-start;gap:10px;border-radius:1rem;padding:10px 12px;background:${isLead ? "rgba(255,255,255,.07)" : "#f1f5f9"};margin-bottom:6px">
            <span style="flex-shrink:0;width:22px;height:22px;border-radius:999px;background:${isLead ? "rgba(125,211,252,.2)" : "#e0f2fe"};color:${isLead ? "#bae6fd" : "#0369a1"};display:inline-flex;align-items:center;justify-content:center;font-size:11px;font-weight:700">${i+1}</span>
            <span style="font-size:13px;line-height:1.6;color:${bodyColor}">${e(item)}</span>
          </div>`).join("")}</div>` : ""}
      </div>`;
    }).join("") : "";

    const generatedAt = new Date().toLocaleString();
    const totalCount = allIssues.length + violations.length;

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Validation Report · ${e(xmlFileName || "connector")}</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;background:#f8fafc;color:#0f172a;padding:32px 16px 64px}
  h2{font-size:22px;font-weight:700;color:#0f172a}
  .container{max-width:820px;margin:0 auto}
  .header{border-radius:1.5rem;border:1px solid #e2e8f0;background:#fff;padding:24px 28px;margin-bottom:20px;box-shadow:0 1px 3px rgba(0,0,0,.06)}
  .stats{display:flex;gap:10px;margin-bottom:16px;flex-wrap:wrap}
  section{margin-bottom:28px}
  section>h3{font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.22em;color:#94a3b8;margin-bottom:12px}
  @media print{body{background:#fff;padding:0}}
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <p style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.24em;color:#0ea5e9">Validation Results</p>
    <h2 style="margin-top:8px">${totalCount === 0 ? "No rule violations found" : `${totalCount} review items`}</h2>
    <p style="margin-top:6px;font-size:13px;color:#64748b">XML: <strong>${e(xmlFileName || "—")}</strong> &nbsp;·&nbsp; PS: <strong>${e(psFileName || "—")}</strong> &nbsp;·&nbsp; ${e(generatedAt)}</p>
    <div class="stats" style="margin-top:16px">${statsRow}</div>
    ${summaryCard}
  </div>

  <section>
    <h3>PowerShell Quality</h3>
    ${psScoreBlock}
    ${auditHtml}
  </section>

  <section>
    <h3>PowerShell Rule Violations</h3>
    ${violationsHtml}
  </section>

  <section>
    <h3>XML Findings · Errors</h3>
    ${issueRows("error")}
  </section>

  <section>
    <h3>XML Findings · Warnings</h3>
    ${issueRows("warning")}
  </section>

  <section>
    <h3>XML Findings · Info</h3>
    ${issueRows("info")}
  </section>

  ${aiSections.length > 0 ? `<section>
    <h3>AI Validation Notes</h3>
    ${aiHtml}
  </section>` : ""}
</div>
</body>
</html>`;

    const blob = new Blob([html], { type: "text/html;charset=utf-8" });
    const downloadUrl = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = downloadUrl;
    anchor.download = `xml-validation-report-${new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-")}.html`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 1500);
  }

  function jumpToIssue(issue: ValidatorIssue) {
    const line = Math.max(1, issue.line || 1);
    const element = lineRefs.current.get(line);
    setActiveSeverity(issue.severity);
    setFocusedIssueId(issue.id);

    if (!resultsOpen) {
      setResultsOpen(true);
      window.setTimeout(() => {
        lineRefs.current.get(line)?.scrollIntoView({ behavior: "smooth", block: "center" });
      }, 80);
      return;
    }

    if (!element) return;
    element.scrollIntoView({ behavior: "smooth", block: "center" });
    element.classList.add("ring-2", "ring-sky-300");
    window.setTimeout(() => element.classList.remove("ring-2", "ring-sky-300"), 900);
  }

  const summary = report?.summary;
  const totalFindings = findings.length;
  const scriptScore = report?.scriptAudit.totalScore ?? 0;
  const scriptScoreColors = scriptScoreTheme(scriptScore);
  const totalResultsCount = totalFindings + scriptViolations.length;

  useEffect(() => {
    if (!findings.length) {
      setActiveSeverity("error");
      return;
    }

    const firstAvailableSeverity =
      severityOrder.find((severity) => findingsBySeverity[severity].length > 0) ?? "error";

    setActiveSeverity((current) =>
      findingsBySeverity[current].length > 0 ? current : firstAvailableSeverity
    );
  }, [findings.length, findingsBySeverity]);

  return (
    <main className="min-h-screen bg-[linear-gradient(180deg,#f8fafc_0%,#eef2ff_52%,#ffffff_100%)]">
      <div className="mx-auto max-w-5xl px-4 py-8">
        <section className="overflow-hidden rounded-[2rem] border border-slate-200/80 bg-slate-950 text-white shadow-[0_30px_80px_rgba(15,23,42,0.28)]">
          <div className="px-6 py-8">
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-sky-300">
              XML Validator
            </p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
              AI validation for connector XML and PowerShell quality.
            </h1>
            <p className="mt-4 max-w-3xl text-sm leading-6 text-slate-300">
              Upload the connector XML and the related PowerShell script. Validation runs through
              AI every time, using the XML-Validator rules markdown as the prompt so the
              PowerShell can be analyzed more deeply than a static parser allows, including script
              security, performance, and quality scoring.
            </p>
          </div>
        </section>

        <section className="mt-6 grid gap-4 md:grid-cols-2">
          <UploadButton
            label="Connector XML"
            detail={xmlFileName || "Select the XML definition you want to validate."}
            accept=".xml,.txt,text/xml"
            onUpload={loadXmlFile}
          />
          <UploadButton
            label="PowerShell Script"
            detail={
              psFileName || "Select the .ps1 or .psm1 file that defines the command signatures."
            }
            accept=".ps1,.psm1,.txt,text/plain"
            onUpload={loadPsFile}
          />
        </section>

        <section className="mt-6 rounded-[1.75rem] border border-slate-200/80 bg-white/90 px-5 py-5 shadow-sm">
          <div className="flex flex-wrap items-center gap-3">
            <button
              onClick={() => {
                void runValidation();
              }}
              disabled={validationBusy || !xmlText.trim() || !psText.trim()}
              className="rounded-full bg-sky-500 px-5 py-2.5 text-sm font-semibold text-slate-950 transition hover:bg-sky-400 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {validationBusy ? "Validating..." : "Validate Files"}
            </button>
            <button
              onClick={() => setResultsOpen(true)}
              disabled={!report}
              className="rounded-full border border-slate-300 px-5 py-2.5 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Open Results
            </button>
            <button
              onClick={() => exportReportHtml()}
              disabled={!report}
              className="rounded-full border border-slate-300 px-5 py-2.5 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Export HTML
            </button>
          </div>

          <div className="mt-4 flex flex-wrap gap-2 text-xs text-slate-500">
            <span className="rounded-full bg-slate-100 px-3 py-1.5">
              XML: {xmlFileName || "not uploaded"}
            </span>
            <span className="rounded-full bg-slate-100 px-3 py-1.5">
              PowerShell: {psFileName || "not uploaded"}
            </span>
            <span className="rounded-full bg-slate-100 px-3 py-1.5">
              Schema context: {summary ? "workspace schema if available" : "sent with validation"}
            </span>
          </div>

          {pageError ? (
            <div className="mt-4 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
              {pageError}
            </div>
          ) : null}

          {report ? (
            <div className="mt-5 flex flex-wrap gap-3">
              {[
                {
                  label: "Errors",
                  value: counts.error,
                  tone: "border-rose-200 bg-rose-50 text-rose-700",
                },
                {
                  label: "Warnings",
                  value: counts.warning,
                  tone: "border-amber-200 bg-amber-50 text-amber-700",
                },
                {
                  label: "Info",
                  value: counts.info,
                  tone: "border-sky-200 bg-sky-50 text-sky-700",
                },
                {
                  label: "Functions",
                  value: summary?.totalFunctions ?? 0,
                  tone: "border-slate-200 bg-slate-50 text-slate-700",
                },
                {
                  label: "PS Score",
                  value: `${scriptScore}/100`,
                  tone: `${scriptScoreColors.shell} ${scriptScoreColors.text}`,
                },
              ].map((card) => (
                <div key={card.label} className={`rounded-2xl border px-4 py-3 ${card.tone}`}>
                  <div className="text-xs font-semibold uppercase tracking-[0.22em]">
                    {card.label}
                  </div>
                  <div className="mt-2 text-2xl font-semibold">{card.value}</div>
                </div>
              ))}
            </div>
          ) : null}
        </section>
      </div>

      {resultsOpen && report ? (
        <div className="fixed inset-0 z-50 bg-slate-950/72 backdrop-blur-sm">
          <button
            type="button"
            aria-label="Close results"
            className="absolute inset-0"
            onClick={() => setResultsOpen(false)}
          />

          <div className="relative mx-auto flex h-full max-w-[1480px] items-center px-3 py-3 sm:px-5 sm:py-5">
            <div className="relative flex h-full w-full overflow-hidden rounded-[2rem] border border-white/20 bg-white shadow-[0_30px_100px_rgba(15,23,42,0.45)]">
              <aside className="flex w-full max-w-[430px] shrink-0 flex-col border-r border-slate-200 bg-[linear-gradient(180deg,#ffffff_0%,#f8fafc_100%)]">
                <div className="border-b border-slate-200 px-5 py-5">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-600">
                        Validation Results
                      </p>
                      <h2 className="mt-2 text-2xl font-semibold text-slate-950">
                        {totalResultsCount === 0
                          ? "No rule violations found"
                          : `${totalResultsCount} review items`}
                      </h2>
                      <p className="mt-2 text-sm leading-6 text-slate-500">
                        Review the PowerShell audit and XML findings, then inspect the highlighted
                        XML lines on the right.
                      </p>
                    </div>
                    <button
                      onClick={() => exportReportHtml()}
                      className="rounded-full border border-slate-300 px-3 py-1.5 text-xs font-semibold text-slate-600 transition hover:bg-slate-50"
                    >
                      Export HTML
                    </button>
                    <button
                      onClick={() => setResultsOpen(false)}
                      className="rounded-full border border-slate-300 px-3 py-1.5 text-xs font-semibold text-slate-600 transition hover:bg-slate-50"
                    >
                      Close
                    </button>
                  </div>

                  <div className="mt-4 grid grid-cols-2 gap-2">
                    {[
                      { label: "Errors", value: counts.error, tone: "text-rose-700" },
                      { label: "Warnings", value: counts.warning, tone: "text-amber-700" },
                      { label: "Info", value: counts.info, tone: "text-sky-700" },
                      { label: "PS Score", value: `${scriptScore}/100`, tone: scriptScoreColors.text },
                    ].map((item) => (
                      <div
                        key={item.label}
                        className="rounded-2xl border border-slate-200 bg-white px-3 py-3"
                      >
                        <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-slate-400">
                          {item.label}
                        </div>
                        <div className={`mt-2 text-xl font-semibold ${item.tone}`}>
                          {item.value}
                        </div>
                      </div>
                    ))}
                  </div>

                  {summary ? (
                    <div className="mt-4 rounded-[1.5rem] border border-slate-200 bg-white px-4 py-4 text-sm text-slate-600">
                      <div className="grid grid-cols-2 gap-3">
                        <div>
                          <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-slate-400">
                            XML Classes
                          </div>
                          <div className="mt-1 font-medium text-slate-900">
                            {summary.xmlClasses.length}
                          </div>
                        </div>
                        <div>
                          <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-slate-400">
                            Global Functions
                          </div>
                          <div className="mt-1 font-medium text-slate-900">
                            {summary.globalFunctions.length}
                          </div>
                        </div>
                      </div>

                      {summary.actualConnectionParameters.length > 0 ? (
                        <p className="mt-3 leading-6">
                          Connection parameters:{" "}
                          <span className="font-medium text-slate-900">
                            {summary.actualConnectionParameters.join(", ")}
                          </span>
                        </p>
                      ) : null}
                    </div>
                  ) : null}
                </div>

                <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">
                  <div className={`rounded-[1.5rem] border px-4 py-4 ${scriptScoreColors.shell}`}>
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <div className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-400">
                          PowerShell Quality
                        </div>
                        <div className={`mt-2 text-4xl font-semibold ${scriptScoreColors.text}`}>
                          {scriptScore}
                          <span className="ml-1 text-base font-medium text-slate-500">/100</span>
                        </div>
                      </div>
                      <div className="rounded-full border border-white/70 bg-white/80 px-3 py-1 text-xs font-semibold text-slate-600">
                        {scriptViolations.length} violated rules
                      </div>
                    </div>

                    <div className="mt-4 h-2 rounded-full bg-white/80">
                      <div
                        className={`h-2 rounded-full transition-all ${scriptScoreColors.bar}`}
                        style={{ width: `${scriptScore}%` }}
                      />
                    </div>

                    <div className="mt-4 flex flex-wrap gap-2">
                      {[
                        { label: "Critical", value: scriptSeverityCounts.critical },
                        { label: "High", value: scriptSeverityCounts.high },
                        { label: "Medium", value: scriptSeverityCounts.medium },
                        { label: "Low", value: scriptSeverityCounts.low },
                      ].map((item) => (
                        <span
                          key={item.label}
                          className="rounded-full border border-white/70 bg-white/80 px-3 py-1 text-xs text-slate-600"
                        >
                          {item.label}: {item.value}
                        </span>
                      ))}
                    </div>

                    {scriptAuditSections.length > 0 ? (
                      <div className="mt-4 space-y-3">
                        {scriptAuditSections.map((section, index) => {
                          const isLead = index === 0;

                          return (
                            <div
                              key={`${section.title}-${index}`}
                              className={`rounded-[1.2rem] border px-4 py-4 ${
                                isLead
                                  ? "border-slate-900 bg-slate-950 text-white"
                                  : "border-white/80 bg-white/80 text-slate-800"
                              }`}
                            >
                              <div
                                className={`text-[11px] font-semibold uppercase tracking-[0.2em] ${
                                  isLead ? "text-sky-300" : "text-slate-400"
                                }`}
                              >
                                {section.title}
                              </div>
                              {section.body ? (
                                <p
                                  className={`mt-2 text-sm leading-6 ${
                                    isLead ? "text-slate-100" : "text-slate-700"
                                  }`}
                                >
                                  {section.body}
                                </p>
                              ) : null}
                              {section.items && section.items.length > 0 ? (
                                <div className="mt-3 space-y-2">
                                  {section.items.map((item, itemIndex) => (
                                    <div
                                      key={`${section.title}-${itemIndex}`}
                                      className={`flex items-start gap-3 rounded-2xl px-3 py-3 ${
                                        isLead
                                          ? "bg-white/8 text-slate-100"
                                          : "bg-slate-50 text-slate-700"
                                      }`}
                                    >
                                      <span
                                        className={`mt-0.5 inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold ${
                                          isLead
                                            ? "bg-sky-400/20 text-sky-100"
                                            : "bg-sky-100 text-sky-700"
                                        }`}
                                      >
                                        {itemIndex + 1}
                                      </span>
                                      <span className="text-sm leading-6">{item}</span>
                                    </div>
                                  ))}
                                </div>
                              ) : null}
                            </div>
                          );
                        })}
                      </div>
                    ) : null}
                  </div>

                  <div className="mt-4">
                    <div className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-400">
                      PowerShell Rule Violations
                    </div>
                    <div className="mt-3 space-y-3">
                      {scriptViolations.length > 0 ? (
                        scriptViolations.map((rule) => {
                          const theme = scriptRuleTheme(rule.severity);

                          return (
                            <div
                              key={rule.id}
                              className={`rounded-[1.35rem] border px-4 py-4 shadow-sm ${theme.card}`}
                            >
                              <div className="flex items-start justify-between gap-3">
                                <div className="flex min-w-0 flex-wrap gap-2">
                                  <span
                                    className={`rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em] ${theme.badge}`}
                                  >
                                    {rule.severity}
                                  </span>
                                  <span className="rounded-full border border-current/15 bg-white/70 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.16em]">
                                    {formatScriptCategory(rule.category)}
                                  </span>
                                </div>
                                <span className="rounded-full border border-current/15 bg-white/70 px-3 py-1 text-xs font-semibold">
                                  -{rule.scoreImpact} pts
                                </span>
                              </div>

                              <h3 className="mt-3 text-sm font-semibold">{rule.title}</h3>
                              <div className="mt-1 text-[11px] font-medium uppercase tracking-[0.16em] text-slate-500">
                                {rule.code}
                                {rule.line ? ` • PS line ${rule.line}` : ""}
                              </div>
                              <p className="mt-3 text-sm leading-6">{rule.evidence}</p>

                              <div className="mt-3 rounded-2xl border border-white/80 bg-white/80 px-3 py-3">
                                <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-400">
                                  Suggested Fix
                                </div>
                                <p className="mt-2 text-sm leading-6 text-slate-700">
                                  {rule.fix}
                                </p>
                              </div>

                              {rule.references && rule.references.length > 0 ? (
                                <div className="mt-3 rounded-2xl border border-white/80 bg-white/80 px-3 py-3">
                                  <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-slate-400">
                                    Related References
                                  </div>
                                  <div className="mt-3 space-y-2">
                                    {rule.references.map((reference) => (
                                      <a
                                        key={reference.id}
                                        href={reference.url}
                                        target="_blank"
                                        rel="noreferrer"
                                        className="block rounded-2xl border border-slate-200 bg-white px-3 py-3 transition hover:border-slate-300 hover:bg-slate-50"
                                      >
                                        <div className="flex flex-wrap items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-500">
                                          <span className="rounded-full border border-slate-200 bg-slate-50 px-2 py-1">
                                            {formatReferenceKind(reference.kind)}
                                          </span>
                                          <span className="rounded-full border border-slate-200 bg-slate-50 px-2 py-1">
                                            {formatReferenceConfidence(reference.confidence)}
                                          </span>
                                        </div>
                                        <div className="mt-2 text-sm font-semibold text-slate-900">
                                          {reference.title}
                                        </div>
                                        <div className="mt-1 text-xs text-slate-500">
                                          {reference.authority}
                                        </div>
                                        <div className="mt-2 break-all text-xs text-sky-700">
                                          {reference.url}
                                        </div>
                                      </a>
                                    ))}
                                  </div>
                                </div>
                              ) : null}
                            </div>
                          );
                        })
                      ) : (
                        <div className="rounded-[1.4rem] border border-emerald-200 bg-emerald-50 px-4 py-4 text-sm leading-6 text-emerald-800">
                          No PowerShell security or performance rule violations were returned for
                          this upload pair.
                        </div>
                      )}
                    </div>
                  </div>

                  <div className="mt-4">
                    <div className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-400">
                      XML Findings
                    </div>
                    <div className="mt-3 grid gap-2">
                      {severityOrder.map((severity) => {
                        const theme = severityTheme(severity);
                        const issueCount = findingsBySeverity[severity].length;
                        const isActive = activeSeverity === severity;

                        return (
                          <button
                            key={severity}
                            onClick={() => {
                              setActiveSeverity(severity);
                              setFocusedIssueId(findingsBySeverity[severity][0]?.id ?? "");
                            }}
                            className={`rounded-[1.35rem] border px-4 py-3 text-left transition ${
                              isActive
                                ? `${theme.panel} ring-2 ring-sky-200`
                                : "border-slate-200 bg-white text-slate-700 hover:border-slate-300 hover:bg-slate-50"
                            }`}
                          >
                            <div className="flex items-center justify-between gap-3">
                              <div className="flex items-center gap-3">
                                <span
                                  className={`h-2.5 w-2.5 rounded-full ${theme.dot}`}
                                />
                                <div>
                                  <div className="text-[11px] font-semibold uppercase tracking-[0.18em]">
                                    {formatSeverityLabel(severity)}
                                  </div>
                                  <div className="mt-1 text-sm text-slate-500">
                                    {issueCount === 0
                                      ? "No messages in this list"
                                      : `${issueCount} ${issueCount === 1 ? "message" : "messages"}`}
                                  </div>
                                </div>
                              </div>
                              <span className="rounded-full border border-current/10 bg-white/70 px-3 py-1 text-xs font-semibold">
                                {issueCount}
                              </span>
                            </div>
                          </button>
                        );
                      })}
                    </div>

                    <div className="mt-4">
                      <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-slate-400">
                        Showing {formatSeverityLabel(activeSeverity)} Messages
                      </div>
                      <div className="mt-3 space-y-3">
                        {activeFindings.length > 0 ? (
                          activeFindings.map((issue) => {
                          const theme = severityTheme(issue.severity);
                          const isFocused = focusedIssueId === issue.id;

                          return (
                            <button
                              key={issue.id}
                              onClick={() => jumpToIssue(issue)}
                              className={`w-full rounded-[1.4rem] border px-4 py-3 text-left transition ${theme.panel} ${
                                isFocused ? "ring-2 ring-sky-300" : ""
                              }`}
                            >
                              <div className="flex items-start gap-3">
                                <span
                                  className={`mt-1 h-2.5 w-2.5 shrink-0 rounded-full ${theme.dot}`}
                                />
                                <div className="min-w-0 flex-1">
                                  <div className="flex flex-wrap items-center gap-2 text-[11px] font-semibold uppercase tracking-[0.18em]">
                                    <span>{formatSeverityLabel(issue.severity)}</span>
                                    <span className="text-slate-500">Line {issue.line}</span>
                                  </div>
                                  <p className="mt-2 text-sm leading-6">{issue.message}</p>
                                  {issue.code ? (
                                    <div className="mt-2 text-[11px] font-medium text-slate-500">
                                      {issue.code}
                                    </div>
                                  ) : null}
                                </div>
                              </div>
                            </button>
                          );
                        })
                        ) : (
                          <div className="rounded-[1.4rem] border border-slate-200 bg-slate-50 px-4 py-4 text-sm leading-6 text-slate-600">
                            No {formatSeverityLabel(activeSeverity).toLowerCase()} messages were
                            returned for this validation run.
                          </div>
                        )}
                      </div>
                    </div>

                    {findings.length === 0 ? (
                        <div className="rounded-[1.4rem] border border-emerald-200 bg-emerald-50 px-4 py-4 text-sm leading-6 text-emerald-800">
                          The current XML passed the rule engine checks for this upload pair.
                        </div>
                      ) : null}
                  </div>

                  <div className="mt-4 rounded-[1.5rem] border border-slate-200 bg-white px-4 py-4">
                    <div className="text-xs font-semibold uppercase tracking-[0.22em] text-slate-400">
                      AI Validation Notes
                    </div>
                    <div className="mt-1 text-sm text-slate-500">
                      Short review cards from the same AI pass that produced the XML findings and
                      PowerShell audit.
                    </div>

                    {analysisSections.length > 0 ? (
                      <div className="mt-4 space-y-3">
                        {analysisSections.map((section, index) => {
                          const isLead = index === 0;

                          return (
                            <div
                              key={`${section.title}-${index}`}
                              className={`rounded-[1.25rem] border px-4 py-4 ${
                                isLead
                                  ? "border-slate-900 bg-slate-950 text-white"
                                  : "border-slate-200 bg-slate-50 text-slate-800"
                              }`}
                            >
                              <div
                                className={`text-[11px] font-semibold uppercase tracking-[0.2em] ${
                                  isLead ? "text-sky-300" : "text-slate-400"
                                }`}
                              >
                                {section.title}
                              </div>

                              {section.body ? (
                                <p
                                  className={`mt-2 text-sm leading-6 ${
                                    isLead ? "text-slate-100" : "text-slate-700"
                                  }`}
                                >
                                  {section.body}
                                </p>
                              ) : null}

                              {section.items && section.items.length > 0 ? (
                                <div className="mt-3 space-y-2">
                                  {section.items.map((item, itemIndex) => (
                                    <div
                                      key={`${section.title}-${itemIndex}`}
                                      className={`flex items-start gap-3 rounded-2xl px-3 py-3 ${
                                        isLead
                                          ? "bg-white/8 text-slate-100"
                                          : "bg-white text-slate-700"
                                      }`}
                                    >
                                      <span
                                        className={`mt-0.5 inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold ${
                                          isLead
                                            ? "bg-sky-400/20 text-sky-100"
                                            : "bg-sky-100 text-sky-700"
                                        }`}
                                      >
                                        {itemIndex + 1}
                                      </span>
                                      <span className="text-sm leading-6">{item}</span>
                                    </div>
                                  ))}
                                </div>
                              ) : null}
                            </div>
                          );
                        })}
                      </div>
                    ) : (
                      <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4 text-sm leading-6 text-slate-600">
                        No additional notes returned.
                      </div>
                    )}
                  </div>
                </div>
              </aside>

              <section className="flex min-w-0 flex-1 flex-col bg-slate-50 text-slate-900">
                <div className="border-b border-slate-200 bg-white px-5 py-4">
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <p className="text-xs font-semibold uppercase tracking-[0.24em] text-sky-600">
                        Affected XML Lines
                      </p>
                      <h3 className="mt-2 text-xl font-semibold">
                        {xmlFileName || "Uploaded XML"}
                      </h3>
                      <p className="mt-2 text-sm leading-6 text-slate-500">
                        Only XML lines referenced by the selected{" "}
                        {formatSeverityLabel(activeSeverity).toLowerCase()} messages are shown here.
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-2 text-xs text-slate-500">
                      <span className="rounded-full border border-slate-200 bg-slate-100 px-3 py-1.5">
                        {visibleLineEntries.length} flagged lines
                      </span>
                      <span className="rounded-full border border-slate-200 bg-slate-100 px-3 py-1.5">
                        {activeFindings.length} {formatSeverityLabel(activeSeverity)} messages
                      </span>
                      <span className="rounded-full border border-slate-200 bg-slate-100 px-3 py-1.5">
                        {summary?.globalFunctions.length ?? 0} global functions
                      </span>
                    </div>
                  </div>
                </div>

                <div className="min-h-0 flex-1 overflow-y-auto px-3 py-3 sm:px-4">
                  {visibleLineEntries.length > 0 ? (
                    <div className="space-y-4">
                      {visibleLineEntries.map(([lineNumber, lineIssues]) => {
                        const lineText = xmlLines[lineNumber - 1] || "";
                        const primaryIssue = lineIssues[0];
                        const theme = severityTheme(primaryIssue.severity);
                        const highlight = splitHighlight(
                          lineText,
                          primaryIssue.column,
                          primaryIssue.length
                        );
                        const lineHasFocus = lineIssues.some(
                          (issue) => issue.id === focusedIssueId
                        );

                        return (
                          <div
                            key={lineNumber}
                            ref={(node) => {
                              if (node) {
                                lineRefs.current.set(lineNumber, node);
                              } else {
                                lineRefs.current.delete(lineNumber);
                              }
                            }}
                            className={`rounded-[1.6rem] border bg-white px-4 py-4 shadow-sm transition ${
                              lineHasFocus
                                ? "border-sky-300 ring-2 ring-sky-200"
                                : "border-slate-200"
                            }`}
                          >
                            <div className="flex flex-wrap items-center justify-between gap-3">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-700">
                                  Line {lineNumber}
                                </span>
                                <span className="rounded-full bg-slate-100 px-3 py-1 text-xs text-slate-500">
                                  {lineIssues.length} {lineIssues.length === 1 ? "finding" : "findings"}
                                </span>
                              </div>
                              {primaryIssue.relatedPath ? (
                                <span className="text-xs text-slate-500">
                                  {primaryIssue.relatedPath}
                                </span>
                              ) : null}
                            </div>

                            <pre className="mt-3 overflow-x-auto rounded-[1.35rem] bg-slate-950 px-4 py-4 font-mono text-[12px] leading-6 text-slate-100 shadow-inner">
                              {highlight.mark ? (
                                <>
                                  {highlight.pre}
                                  <mark className={`rounded px-0.5 text-slate-950 ${theme.inline}`}>
                                    {highlight.mark}
                                  </mark>
                                  {highlight.post}
                                </>
                              ) : (
                                lineText || " "
                              )}
                            </pre>

                            <div className="mt-3 space-y-2">
                              {lineIssues.map((issue) => {
                                const bubbleTheme = severityTheme(issue.severity);
                                const isFocused = focusedIssueId === issue.id;

                                return (
                                  <button
                                    key={issue.id}
                                    onClick={() => setFocusedIssueId(issue.id)}
                                    className={`flex w-full items-start gap-3 rounded-[1.2rem] border px-4 py-3 text-left text-sm leading-6 shadow-sm transition ${bubbleTheme.bubble} ${
                                      isFocused ? "ring-2 ring-sky-200" : ""
                                    }`}
                                  >
                                    <span
                                      className={`mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full ${bubbleTheme.dot}`}
                                    />
                                    <span className="min-w-0 flex-1">
                                      <span className="block text-[11px] font-semibold uppercase tracking-[0.18em]">
                                        {formatSeverityLabel(issue.severity)}
                                        {issue.code ? ` • ${issue.code}` : ""}
                                      </span>
                                      <span className="mt-1 block">{issue.message}</span>
                                      {issue.relatedPath ? (
                                        <span className="mt-1 block text-xs text-slate-500">
                                          {issue.relatedPath}
                                        </span>
                                      ) : null}
                                    </span>
                                  </button>
                                );
                              })}
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  ) : (
                    <div className="rounded-[1.5rem] border border-slate-200 bg-slate-50 px-5 py-5 text-sm leading-6 text-slate-600">
                      No XML lines are attached to the selected{" "}
                      {formatSeverityLabel(activeSeverity).toLowerCase()} messages.
                    </div>
                  )}
                </div>
              </section>
            </div>
          </div>
        </div>
      ) : null}
    </main>
  );
}
