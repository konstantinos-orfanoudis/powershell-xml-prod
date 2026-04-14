import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  mkdir,
  readFile,
  readdir,
  stat,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { SSCP_DOMAINS } from "@/lib/sscp/catalog";
import { ImportedNoteChunk, SscpDomainId } from "@/lib/sscp/types";

const execFileAsync = promisify(execFile);

const PDF_LIBRARY_DIR =
  process.env.SSCP_COACH_DOC_DIR ??
  "C:\\Users\\aiuser\\Desktop\\SSCP-CISSP-Coach\\doc";
const WORK_DIR = path.join(
  process.env.SSCP_COACH_RUNTIME_DIR ?? path.join(os.tmpdir(), "sscp-cissp-coach"),
  "pdf-corpus",
);
const CACHE_FILE = path.join(WORK_DIR, "notes-cache.json");

interface NotesCache {
  corpusDir: string;
  corpusSignature: string;
  chunks: ImportedNoteChunk[];
}

async function walkPdfFiles(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const nextPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        return walkPdfFiles(nextPath);
      }
      return entry.name.toLowerCase().endsWith(".pdf") ? [nextPath] : [];
    }),
  );
  return nested.flat();
}

async function buildCorpusSignature(pdfFiles: string[]): Promise<string> {
  const parts = await Promise.all(
    pdfFiles.map(async (filePath) => {
      const fileStat = await stat(filePath);
      return `${path.basename(filePath)}:${fileStat.size}:${Math.round(fileStat.mtimeMs)}`;
    }),
  );
  return parts.sort().join("|");
}

function scoreDomainMatch(text: string, domainId: SscpDomainId): number {
  const domain = SSCP_DOMAINS.find((entry) => entry.id === domainId);
  if (!domain) return 0;

  const lower = text.toLowerCase();
  const terms = [
    domain.title,
    domain.summary,
    ...domain.glossary,
    ...domain.objectives.flatMap((objective) => [objective.title, objective.summary, ...objective.keywords]),
  ]
    .join(" ")
    .toLowerCase()
    .split(/[^a-z0-9]+/i)
    .filter((term) => term.length >= 4);

  return [...new Set(terms)].reduce((score, term) => {
    return lower.includes(term) ? score + 1 : score;
  }, 0);
}

function inferDomainFromText(fileName: string, text: string): SscpDomainId {
  const haystack = `${fileName} ${text}`.toLowerCase();
  const ranked = SSCP_DOMAINS.map((domain) => ({
    domainId: domain.id,
    score: scoreDomainMatch(haystack, domain.id),
  })).sort((left, right) => right.score - left.score);

  if ((ranked[0]?.score ?? 0) > 0) {
    return ranked[0]!.domainId;
  }

  if (haystack.includes("access") || haystack.includes("identity")) return "access-controls";
  if (haystack.includes("incident") || haystack.includes("recovery")) return "incident-response-recovery";
  if (haystack.includes("crypto") || haystack.includes("encrypt")) return "cryptography";
  if (haystack.includes("network") || haystack.includes("protocol")) return "network-communications-security";
  if (haystack.includes("application") || haystack.includes("software")) return "systems-application-security";
  if (haystack.includes("risk") || haystack.includes("audit")) return "risk-identification-monitoring-analysis";
  return "security-concepts-practices";
}

function extractKeywords(text: string, domainId: SscpDomainId): string[] {
  const glossary = SSCP_DOMAINS.find((domain) => domain.id === domainId)?.glossary ?? [];
  const lower = text.toLowerCase();
  const matches = glossary.filter((term) => lower.includes(term.toLowerCase()));
  if (matches.length) return matches.slice(0, 6);
  return lower
    .split(/[^a-z0-9]+/i)
    .filter((part) => part.length > 5)
    .slice(0, 6);
}

function chunkText(fileName: string, text: string): ImportedNoteChunk[] {
  const normalized = text
    .replace(/\r/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  const paragraphs = normalized
    .split(/\n\s*\n/)
    .map((part) => part.replace(/\s+/g, " ").trim())
    .filter((part) => part.length >= 220);

  const blocks = paragraphs.length
    ? paragraphs
    : normalized.match(/.{1,950}(?:\s|$)/g)?.map((part) => part.trim()) ?? [];

  return blocks.slice(0, 28).map((excerpt, index) => {
    const domainId = inferDomainFromText(fileName, excerpt);
    return {
      id: `${path.basename(fileName, ".pdf").toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${index + 1}`,
      domainId,
      title:
        excerpt.split(/[.!?]/)[0]?.slice(0, 100) ||
        `${path.basename(fileName, ".pdf")} ${index + 1}`,
      fileName: path.basename(fileName),
      excerpt,
      sectionLabel: `Section ${index + 1}`,
      keywords: extractKeywords(excerpt, domainId),
      sourceType: "user_notes",
    };
  });
}

async function parsePdf(filePath: string): Promise<string> {
  const scriptPath = path.join(process.cwd(), "scripts", "extract-pdf-text.cjs");
  const { stdout } = await execFileAsync(
    "node",
    [scriptPath, filePath],
    {
      cwd: process.cwd(),
      maxBuffer: 24 * 1024 * 1024,
    },
  );
  const payload = JSON.parse(stdout) as { text?: string };
  return payload.text ?? "";
}

export async function loadImportedNotes(force = false): Promise<ImportedNoteChunk[]> {
  await mkdir(WORK_DIR, { recursive: true });

  const pdfFiles = await walkPdfFiles(PDF_LIBRARY_DIR);
  if (!pdfFiles.length) {
    throw new Error(`No PDF study files were found in ${PDF_LIBRARY_DIR}.`);
  }

  const corpusSignature = await buildCorpusSignature(pdfFiles);
  if (!force) {
    try {
      const cached = JSON.parse(await readFile(CACHE_FILE, "utf8")) as NotesCache;
      if (cached.corpusDir === PDF_LIBRARY_DIR && cached.corpusSignature === corpusSignature) {
        return cached.chunks;
      }
    } catch {
      // Ignore cache misses and rebuild below.
    }
  }

  const chunks: ImportedNoteChunk[] = [];
  for (const pdfFile of pdfFiles) {
    const text = await parsePdf(pdfFile);
    if (!text.trim()) continue;
    chunks.push(...chunkText(pdfFile, text));
  }

  const cachePayload: NotesCache = {
    corpusDir: PDF_LIBRARY_DIR,
    corpusSignature,
    chunks,
  };
  await writeFile(CACHE_FILE, JSON.stringify(cachePayload, null, 2), "utf8");
  return chunks;
}

export async function loadCachedImportedNotes(): Promise<ImportedNoteChunk[]> {
  try {
    const cached = JSON.parse(await readFile(CACHE_FILE, "utf8")) as NotesCache;
    if (cached.corpusDir === PDF_LIBRARY_DIR) {
      return cached.chunks;
    }
  } catch {
    // Fall through to lazy corpus load.
  }

  return loadImportedNotes(false);
}
