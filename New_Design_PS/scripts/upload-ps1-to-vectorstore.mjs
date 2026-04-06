/**
 * One-time setup script: upload PS1 files to OpenAI vector store
 * and attach the vector store to the assistant.
 *
 * Usage:
 *   node scripts/upload-ps1-to-vectorstore.mjs <path-to-ps1-folder>
 *
 * Example:
 *   node scripts/upload-ps1-to-vectorstore.mjs C:\MyConnectors\ps1-files
 *
 * Requirements:
 *   - OPENAI_API_KEY in .env.local (read automatically)
 *   - OPENAI_ASSISTANT_ID in .env.local
 *   - NEXT_PUBLIC_VECTOR_STORE_ID in .env.local (optional — creates new if missing)
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

// ── Read .env.local manually (no dotenv dependency needed) ───────────────────
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const envPath = path.join(__dirname, "..", ".env.local");
const envVars = {};
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
    const m = line.match(/^([^#=]+)=(.*)$/);
    if (m) envVars[m[1].trim()] = m[2].trim();
  }
}

const OPENAI_API_KEY     = envVars.OPENAI_API_KEY     || process.env.OPENAI_API_KEY;
const ASSISTANT_ID       = envVars.OPENAI_ASSISTANT_ID || process.env.OPENAI_ASSISTANT_ID;
const VECTOR_STORE_ID    = envVars.NEXT_PUBLIC_VECTOR_STORE_ID || process.env.NEXT_PUBLIC_VECTOR_STORE_ID;

if (!OPENAI_API_KEY) { console.error("Missing OPENAI_API_KEY"); process.exit(1); }
if (!ASSISTANT_ID)   { console.error("Missing OPENAI_ASSISTANT_ID"); process.exit(1); }

const PS1_FOLDER = process.argv[2];
if (!PS1_FOLDER || !fs.existsSync(PS1_FOLDER)) {
  console.error("Usage: node scripts/upload-ps1-to-vectorstore.mjs <path-to-ps1-folder>");
  process.exit(1);
}

// ── OpenAI helpers ────────────────────────────────────────────────────────────
const BASE = "https://api.openai.com/v1";

async function api(method, endpoint, body, isFormData = false) {
  const headers = {
    Authorization: `Bearer ${OPENAI_API_KEY}`,
    "OpenAI-Beta": "assistants=v2",
  };
  if (!isFormData) headers["Content-Type"] = "application/json";
  const res = await fetch(`${BASE}${endpoint}`, {
    method,
    headers,
    body: isFormData ? body : (body ? JSON.stringify(body) : undefined),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${endpoint} → ${res.status}: ${text}`);
  return JSON.parse(text);
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  // 1. Find all PS1/PSM1 files (recurse one level into subfolders)
  const EXTS = [".ps1", ".psm1"];
  let ps1Files = [];

  function collectFiles(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        collectFiles(path.join(dir, entry.name));
      } else if (EXTS.includes(path.extname(entry.name).toLowerCase())) {
        ps1Files.push(path.join(dir, entry.name));
      }
    }
  }
  collectFiles(PS1_FOLDER);

  if (ps1Files.length === 0) {
    console.error("No .ps1/.psm1 files found in", PS1_FOLDER);
    process.exit(1);
  }
  console.log(`Found ${ps1Files.length} file(s):`, ps1Files.map(f => path.basename(f)));

  // 2. Use existing vector store or create a new one
  let vsId = VECTOR_STORE_ID;
  if (vsId) {
    console.log(`\nUsing existing vector store: ${vsId}`);
  } else {
    console.log("\nCreating new vector store...");
    const vs = await api("POST", "/vector_stores", { name: "PS1 Connector Repository" });
    vsId = vs.id;
    console.log(`Created vector store: ${vsId}`);
    console.log(`Add this to .env.local: NEXT_PUBLIC_VECTOR_STORE_ID=${vsId}`);
  }

  // 3. Upload each PS1 file and add to the vector store
  console.log("\nUploading files...");
  const fileIds = [];
  for (const filePath of ps1Files) {
    const fileName = path.basename(filePath);
    const content  = fs.readFileSync(filePath);

    // Upload file via multipart form
    // OpenAI doesn't accept .ps1/.psm1 — upload as .txt (content unchanged)
    const uploadName = fileName.replace(/\.(ps1|psm1)$/i, ".txt");
    const form = new FormData();
    form.append("purpose", "assistants");
    form.append("file", new Blob([content], { type: "text/plain" }), uploadName);

    const uploaded = await api("POST", "/files", form, true);
    fileIds.push(uploaded.id);
    console.log(`  ✓ ${fileName} → file id: ${uploaded.id}`);
  }

  // 4. Add all files to the vector store in one batch
  console.log(`\nAdding ${fileIds.length} file(s) to vector store ${vsId}...`);
  const batch = await api("POST", `/vector_stores/${vsId}/file_batches`, { file_ids: fileIds });
  console.log(`  Batch status: ${batch.status} (id: ${batch.id})`);

  // Poll batch until done
  let batchStatus = batch.status;
  while (batchStatus === "in_progress" || batchStatus === "queued") {
    await new Promise(r => setTimeout(r, 2000));
    const b = await api("GET", `/vector_stores/${vsId}/file_batches/${batch.id}`);
    batchStatus = b.status;
    console.log(`  Batch status: ${batchStatus} — processed: ${b.file_counts?.completed ?? 0}/${fileIds.length}`);
  }

  if (batchStatus !== "completed") {
    console.error(`Batch ended with status: ${batchStatus}`);
    process.exit(1);
  }

  // 5. Attach vector store to assistant (enable file_search tool)
  console.log(`\nAttaching vector store to assistant ${ASSISTANT_ID}...`);
  await api("POST", `/assistants/${ASSISTANT_ID}`, {
    tools: [{ type: "file_search" }],
    tool_resources: {
      file_search: { vector_store_ids: [vsId] },
    },
  });
  console.log("  ✓ Done");

  console.log(`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Setup complete!
Vector store: ${vsId}
Assistant:    ${ASSISTANT_ID}
Files loaded: ${fileIds.length}

The assistant will now search the PS1 repository
automatically on every run — no Azure needed.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
}

main().catch(e => { console.error(e.message); process.exit(1); });
