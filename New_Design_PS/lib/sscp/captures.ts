import { mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { ExtensionCapture } from "@/lib/sscp/types";

const CAPTURE_DIR = path.join(
  process.env.SSCP_COACH_RUNTIME_DIR ?? path.join(os.tmpdir(), "sscp-cissp-coach"),
  "sscp-extension",
);
const CAPTURE_FILE = path.join(CAPTURE_DIR, "captures.json");

async function ensureCaptureFile() {
  await mkdir(CAPTURE_DIR, { recursive: true });
  try {
    await readFile(CAPTURE_FILE, "utf8");
  } catch {
    await writeFile(CAPTURE_FILE, "[]", "utf8");
  }
}

export async function listExtensionCaptures(): Promise<ExtensionCapture[]> {
  await ensureCaptureFile();
  const raw = await readFile(CAPTURE_FILE, "utf8");
  const captures = JSON.parse(raw) as ExtensionCapture[];
  return captures.sort((left, right) => right.createdAt.localeCompare(left.createdAt));
}

export async function addExtensionCapture(
  capture: Omit<ExtensionCapture, "id" | "createdAt" | "processed">,
): Promise<ExtensionCapture> {
  const captures = await listExtensionCaptures();
  const nextCapture: ExtensionCapture = {
    id: `cap-${Date.now()}`,
    createdAt: new Date().toISOString(),
    processed: false,
    ...capture,
  };
  captures.unshift(nextCapture);
  await writeFile(CAPTURE_FILE, JSON.stringify(captures, null, 2), "utf8");
  return nextCapture;
}

export async function markCaptureProcessed(id: string): Promise<void> {
  const captures = await listExtensionCaptures();
  const next = captures.map((capture) =>
    capture.id === id ? { ...capture, processed: true } : capture,
  );
  await writeFile(CAPTURE_FILE, JSON.stringify(next, null, 2), "utf8");
}
