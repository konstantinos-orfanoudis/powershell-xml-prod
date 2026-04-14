import type {
  ScriptRuleViolation,
  ValidationReportExportRequest,
  ValidatorIssue,
} from "@/app/XML-Validator/types";

type PdfLine = {
  text: string;
  size: number;
  bold?: boolean;
  indent?: number;
  gapAfter?: number;
};

type PdfPage = {
  content: string;
};

const PAGE_WIDTH = 612;
const PAGE_HEIGHT = 792;
const LEFT_MARGIN = 54;
const TOP_MARGIN = 56;
const BOTTOM_MARGIN = 56;

function sanitizePdfText(text: string) {
  return String(text ?? "")
    .replace(/[^\x09\x0A\x0D\x20-\x7E]/g, " ")
    .replace(/\\/g, "\\\\")
    .replace(/\(/g, "\\(")
    .replace(/\)/g, "\\)")
    .replace(/\s+/g, " ")
    .trim();
}

function wrapText(text: string, maxChars: number) {
  const sanitized = sanitizePdfText(text);
  if (!sanitized) return [""];

  const words = sanitized.split(" ");
  const lines: string[] = [];
  let current = "";

  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length <= maxChars) {
      current = candidate;
      continue;
    }

    if (current) {
      lines.push(current);
      current = word;
      continue;
    }

    lines.push(word.slice(0, maxChars));
    current = word.slice(maxChars);
  }

  if (current) lines.push(current);
  return lines;
}

function formatTimestamp(isoText?: string) {
  const date = isoText ? new Date(isoText) : new Date();
  if (Number.isNaN(date.getTime())) return new Date().toISOString();
  return date.toISOString().replace("T", " ").replace(/\.\d+Z$/, " UTC");
}

function severityBucket(issues: ValidatorIssue[], severity: ValidatorIssue["severity"]) {
  return issues
    .filter((issue) => issue.severity === severity)
    .sort((left, right) => left.line - right.line);
}

function pushWrappedLine(lines: PdfLine[], text: string, options?: Partial<PdfLine>) {
  const size = options?.size ?? 10;
  const indent = options?.indent ?? 0;
  const maxChars = Math.max(28, Math.floor((92 - indent * 1.6) * (10 / size)));
  const wrapped = wrapText(text, maxChars);

  wrapped.forEach((segment, index) => {
    lines.push({
      text: segment,
      size,
      bold: options?.bold,
      indent,
      gapAfter: index === wrapped.length - 1 ? options?.gapAfter : undefined,
    });
  });
}

function addIssueSection(
  lines: PdfLine[],
  title: string,
  issues: ValidatorIssue[]
) {
  lines.push({ text: title, size: 12, bold: true, gapAfter: 4 });

  if (issues.length === 0) {
    pushWrappedLine(lines, "No findings in this severity group.", {
      size: 10,
      indent: 1,
      gapAfter: 6,
    });
    return;
  }

  for (const issue of issues) {
    pushWrappedLine(lines, `${issue.code || "xml.issue"} - line ${issue.line}`, {
      size: 10,
      bold: true,
      indent: 1,
    });
    pushWrappedLine(lines, issue.message, { size: 10, indent: 2 });
    if (issue.relatedPath) {
      pushWrappedLine(lines, `XML path: ${issue.relatedPath}`, {
        size: 9,
        indent: 2,
      });
    }
    lines.push({ text: "", size: 9, gapAfter: 3 });
  }
}

function addScriptViolation(lines: PdfLine[], rule: ScriptRuleViolation) {
  pushWrappedLine(
    lines,
    `${rule.code} - ${rule.title}${rule.line ? ` (PS line ${rule.line})` : ""}`,
    {
      size: 10,
      bold: true,
      indent: 1,
    }
  );
  pushWrappedLine(
    lines,
    `Severity: ${rule.severity} | Category: ${rule.category} | Score impact: -${rule.scoreImpact}`,
    {
      size: 9,
      indent: 2,
    }
  );
  pushWrappedLine(lines, `Evidence: ${rule.evidence}`, { size: 10, indent: 2 });
  pushWrappedLine(lines, `Suggested fix: ${rule.fix}`, { size: 10, indent: 2 });

  if (rule.references && rule.references.length > 0) {
    pushWrappedLine(lines, "References:", {
      size: 9,
      indent: 2,
      bold: true,
    });

    for (const reference of rule.references) {
      pushWrappedLine(
        lines,
        `[${reference.kind}] ${reference.title} (${reference.authority}, ${reference.confidence})`,
        {
          size: 9,
          indent: 3,
        }
      );
      pushWrappedLine(lines, reference.url, { size: 8, indent: 4 });
    }
  }

  lines.push({ text: "", size: 9, gapAfter: 3 });
}

function buildReportLines(input: ValidationReportExportRequest) {
  const { report } = input;
  const errors = severityBucket(report.issues, "error");
  const warnings = severityBucket(report.issues, "warning");
  const info = severityBucket(report.issues, "info");
  const scriptViolations = [...report.scriptAudit.violatedRules].sort(
    (left, right) => right.scoreImpact - left.scoreImpact
  );

  const lines: PdfLine[] = [
    { text: "XML Validator Report", size: 18, bold: true, gapAfter: 8 },
    {
      text: `Generated: ${formatTimestamp(input.generatedAt)}`,
      size: 10,
      gapAfter: 3,
    },
    {
      text: `XML file: ${input.xmlFileName || "uploaded-xml.xml"}`,
      size: 10,
    },
    {
      text: `PowerShell file: ${input.psFileName || "uploaded-script.ps1"}`,
      size: 10,
      gapAfter: 8,
    },
    { text: "Summary", size: 13, bold: true, gapAfter: 4 },
    {
      text: `Errors: ${errors.length} | Warnings: ${warnings.length} | Info: ${info.length}`,
      size: 10,
    },
    {
      text: `PowerShell total score: ${report.scriptAudit.totalScore}/100 | Violated rules: ${scriptViolations.length}`,
      size: 10,
      gapAfter: 6,
    },
    {
      text: `Detected XML classes: ${report.summary.xmlClasses.length} | Global functions: ${report.summary.globalFunctions.length} | Custom commands: ${report.summary.customCommands.length}`,
      size: 10,
      gapAfter: 10,
    },
    { text: "XML Findings", size: 13, bold: true, gapAfter: 4 },
  ];

  addIssueSection(lines, "Errors", errors);
  addIssueSection(lines, "Warnings", warnings);
  addIssueSection(lines, "Info", info);

  lines.push({ text: "PowerShell Rule Violations", size: 13, bold: true, gapAfter: 4 });
  if (scriptViolations.length === 0) {
    pushWrappedLine(lines, "No PowerShell rule violations were returned.", {
      size: 10,
      indent: 1,
      gapAfter: 6,
    });
  } else {
    for (const rule of scriptViolations) {
      addScriptViolation(lines, rule);
    }
  }

  lines.push({ text: "AI Validation Notes", size: 13, bold: true, gapAfter: 4 });
  pushWrappedLine(lines, report.analysis || "No additional AI notes returned.", {
    size: 10,
    indent: 1,
    gapAfter: 6,
  });

  lines.push({ text: "PowerShell Audit Summary", size: 13, bold: true, gapAfter: 4 });
  pushWrappedLine(
    lines,
    report.scriptAudit.summary || "No PowerShell audit summary returned.",
    {
      size: 10,
      indent: 1,
      gapAfter: 6,
    }
  );

  return lines;
}

function buildPages(lines: PdfLine[]): PdfPage[] {
  const pages: PdfPage[] = [];
  let y = PAGE_HEIGHT - TOP_MARGIN;
  let segments: string[] = [];

  function flushPage() {
    if (segments.length === 0) return;
    pages.push({ content: segments.join("\n") });
    segments = [];
    y = PAGE_HEIGHT - TOP_MARGIN;
  }

  for (const line of lines) {
    const indent = line.indent ?? 0;
    const lineHeight = line.size + 4;

    if (y - lineHeight < BOTTOM_MARGIN) {
      flushPage();
    }

    const x = LEFT_MARGIN + indent * 18;
    const font = line.bold ? "/F2" : "/F1";
    segments.push(
      `BT ${font} ${line.size} Tf 1 0 0 1 ${x} ${y} Tm (${line.text || " "}) Tj ET`
    );
    y -= lineHeight + (line.gapAfter ?? 0);
  }

  flushPage();
  return pages;
}

function buildPdfDocument(pages: PdfPage[]) {
  const objects: string[] = [];

  function addObject(value: string) {
    objects.push(value);
    return objects.length;
  }

  const fontNormalId = addObject("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  const fontBoldId = addObject("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>");
  const pageObjectIds: number[] = [];
  const contentObjectIds: number[] = [];

  for (const page of pages) {
    const contentId = addObject(
      `<< /Length ${Buffer.byteLength(page.content, "utf8")} >>\nstream\n${page.content}\nendstream`
    );
    contentObjectIds.push(contentId);
    pageObjectIds.push(0);
  }

  const pagesId = addObject("<< /Type /Pages /Kids [] /Count 0 >>");

  pageObjectIds.forEach((_, index) => {
    const pageId = addObject(
      `<< /Type /Page /Parent ${pagesId} 0 R /MediaBox [0 0 ${PAGE_WIDTH} ${PAGE_HEIGHT}] /Resources << /Font << /F1 ${fontNormalId} 0 R /F2 ${fontBoldId} 0 R >> >> /Contents ${contentObjectIds[index]} 0 R >>`
    );
    pageObjectIds[index] = pageId;
  });

  objects[pagesId - 1] = `<< /Type /Pages /Kids [${pageObjectIds
    .map((id) => `${id} 0 R`)
    .join(" ")}] /Count ${pageObjectIds.length} >>`;

  const catalogId = addObject(`<< /Type /Catalog /Pages ${pagesId} 0 R >>`);

  let pdf = "%PDF-1.4\n";
  const offsets = [0];

  objects.forEach((object, index) => {
    offsets.push(Buffer.byteLength(pdf, "utf8"));
    pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });

  const xrefOffset = Buffer.byteLength(pdf, "utf8");
  pdf += `xref\n0 ${objects.length + 1}\n`;
  pdf += "0000000000 65535 f \n";
  for (let index = 1; index < offsets.length; index += 1) {
    pdf += `${String(offsets[index]).padStart(10, "0")} 00000 n \n`;
  }

  pdf += `trailer\n<< /Size ${objects.length + 1} /Root ${catalogId} 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;

  return Buffer.from(pdf, "utf8");
}

export function buildValidationReportPdf(input: ValidationReportExportRequest) {
  const pages = buildPages(buildReportLines(input));
  return buildPdfDocument(pages.length > 0 ? pages : [{ content: "" }]);
}
