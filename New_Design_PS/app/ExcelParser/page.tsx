"use client";
import React, { useMemo, useRef, useState } from "react";
import * as XLSX from "xlsx";

/**
 * Excel Smart Parser → CSV Generator
 *
 * Key features:
 * ✅ Records CSV (formerly Roles CSV): supports mapping ranges that are single-column (by row) OR single-row (by column)
 * ✅ Assignments CSV: supports Object A range, Object B range, Matrix range
 * ✅ Assignments CSV: supports OPTIONAL extra output columns (user-defined), each with its own range(s)
 * ✅ Filters: =, <, >, !=, like, not like. Can compare Output column OR Sheet range (Auto)
 * ✅ Duplicates: found on filtered output
 *
 * UI:
 * ✅ Cleaner design, black primary buttons (higher contrast)
 * ✅ No Pick buttons
 * ✅ No sheet preview
 */

type Grid = string[][];
type Step = 0 | 1 | 2 | 3 | 4;
type Mode = "roles" | "assignments";

type RangeA1 = { r0: number; c0: number; r1: number; c1: number };

type RolesColumnSpec = {
  header: string;
  rangesA1: string[];
};

type AssignExtraColumnSpec = {
  header: string;
  rangesA1: string[];
};

type FilterOp = "eq" | "neq" | "lt" | "gt" | "like" | "notLike" | "isEmpty" | "isNotEmpty";
type FilterSource = "output" | "sheet";

type FilterCondition = {
  id: string;
  source: FilterSource;
  field: string;
  sheetRangeA1: string;
  op: FilterOp;
  value: string;
};

type TemplateV1 = {
  version: 1;
  mode: Mode;
  // Records config
  rolesColumns: RolesColumnSpec[];
  requiredRoleHeader: string;
  rolesFilters: FilterCondition[];
  // Assignments config
  assignAHeader: string;
  assignBHeader: string;
  assignObjARange: string;
  assignObjBRange: string;
  assignMatrixRange: string;
  assignMarkValues: string;
  assignExtraColumns: AssignExtraColumnSpec[];
  assignFilters: FilterCondition[];
  // Optional UX
  sheetName?: string;
};


// ---------- helpers ----------
function clamp(n: number, lo: number, hi: number) {
  return Math.max(lo, Math.min(hi, n));
}

function uid() {
  return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function lettersToCol(letters: string): number {
  let n = 0;
  const up = letters.toUpperCase();
  for (let i = 0; i < up.length; i++) n = n * 26 + (up.charCodeAt(i) - 64);
  return n - 1;
}

function parseA1Range(a1: string): RangeA1 | null {
  const cleaned = a1.trim().toUpperCase();
  if (!cleaned) return null;

  const parts = cleaned.split(":");
  const parseCell = (s: string) => {
    const m = s.match(/^([A-Z]+)(\d+)$/);
    if (!m) return null;
    const c = lettersToCol(m[1]);
    const r = parseInt(m[2], 10) - 1;
    if (Number.isNaN(r) || r < 0 || c < 0) return null;
    return { r, c };
  };

  const a = parseCell(parts[0]);
  if (!a) return null;
  if (parts.length === 1) return { r0: a.r, c0: a.c, r1: a.r, c1: a.c };

  const b = parseCell(parts[1]);
  if (!b) return null;
  return { r0: a.r, c0: a.c, r1: b.r, c1: b.c };
}

function normalizeRange(rng: RangeA1, grid: Grid): RangeA1 {
  const rows = grid.length;
  const cols = grid[0]?.length ?? 0;
  const r0 = clamp(Math.min(rng.r0, rng.r1), 0, Math.max(0, rows - 1));
  const r1 = clamp(Math.max(rng.r0, rng.r1), 0, Math.max(0, rows - 1));
  const c0 = clamp(Math.min(rng.c0, rng.c1), 0, Math.max(0, cols - 1));
  const c1 = clamp(Math.max(rng.c0, rng.c1), 0, Math.max(0, cols - 1));
  return { r0, c0, r1, c1 };
}

function getRange2D(grid: Grid, rng: RangeA1): string[][] {
  const n = normalizeRange(rng, grid);
  const out: string[][] = [];
  for (let r = n.r0; r <= n.r1; r++) {
    const row: string[] = [];
    for (let c = n.c0; c <= n.c1; c++) row.push((grid[r]?.[c] ?? "").toString());
    out.push(row);
  }
  return out;
}

function getRangeVector(grid: Grid, rng: RangeA1): string[] {
  const n = normalizeRange(rng, grid);
  const h = n.r1 - n.r0 + 1;
  const w = n.c1 - n.c0 + 1;
  const block = getRange2D(grid, n);

  if (w === 1) return block.map((r) => (r[0] ?? "").toString());
  if (h === 1) return block[0].map((v) => (v ?? "").toString());
  return block.flat().map((v) => (v ?? "").toString());
}

// ---- Roles/Records keying: row or col ----
type RoleKey = string; // "r:12" or "c:30"
const rowKey = (r: number): RoleKey => `r:${r}`;
const colKey = (c: number): RoleKey => `c:${c}`;

function parseRoleKey(k: RoleKey): { kind: "row" | "col"; idx: number } | null {
  const m = k.match(/^([rc]):(\d+)$/);
  if (!m) return null;
  return { kind: m[1] === "r" ? "row" : "col", idx: parseInt(m[2], 10) };
}

/**
 * Records mapping:
 * - Single column => map by row (r:idx)
 * - Single row    => map by col (c:idx)
 * - Block         => join per row (r:idx) with warning
 */
function getRolesMap(
  grid: Grid,
  rng: RangeA1
): { map: Map<RoleKey, string>; warning?: string; keyKind: "row" | "col" } {
  const n = normalizeRange(rng, grid);
  const h = n.r1 - n.r0 + 1;
  const w = n.c1 - n.c0 + 1;

  if (w === 1) {
    const map = new Map<RoleKey, string>();
    for (let r = n.r0; r <= n.r1; r++) map.set(rowKey(r), (grid[r]?.[n.c0] ?? "").toString().trim());
    return { map, keyKind: "row" };
  }

  if (h === 1) {
    const map = new Map<RoleKey, string>();
    for (let c = n.c0; c <= n.c1; c++) map.set(colKey(c), (grid[n.r0]?.[c] ?? "").toString().trim());
    return { map, keyKind: "col" };
  }

  const map = new Map<RoleKey, string>();
  for (let r = n.r0; r <= n.r1; r++) {
    const parts: string[] = [];
    for (let c = n.c0; c <= n.c1; c++) {
      const v = (grid[r]?.[c] ?? "").toString().trim();
      if (v) parts.push(v);
    }
    map.set(rowKey(r), parts.join(" "));
  }
  return { map, keyKind: "row", warning: "Range is a block; values are joined per row." };
}

function csvEscape(value: string): string {
  const v = value ?? "";
  const mustQuote = /[",\n\r]/.test(v);
  const escaped = v.replace(/"/g, '""');
  return mustQuote ? `"${escaped}"` : escaped;
}

function toCsv(headers: string[], rows: Record<string, any>[]) {
  const lines: string[] = [];
  lines.push(headers.map(csvEscape).join(","));
  for (const row of rows) lines.push(headers.map((h) => csvEscape((row[h] ?? "").toString())).join(","));
  return lines.join("\n");
}

function downloadText(filename: string, text: string) {
  const isTxt = filename.toLowerCase().endsWith(".txt");
  const mime = isTxt ? "text/plain;charset=utf-8" : "text/csv;charset=utf-8";
  const blob = new Blob([text], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}


function downloadJson(filename: string, data: unknown) {
  const text = JSON.stringify(data, null, 2);
  const blob = new Blob([text], { type: "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function makeUniqueHeaders(headers: string[]) {
  const seen = new Map<string, number>();
  return headers.map((h) => {
    const base = h.trim() || "Column";
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    return n === 1 ? base : `${base}_${n}`;
  });
}



function parseCsvText(text: string): { headers: string[]; rows: Record<string, string>[] } {
  const s = (text ?? "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");

  const rowsRaw: string[][] = [];
  let row: string[] = [];
  let cur = "";
  let inQuotes = false;

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];

    if (inQuotes) {
      if (ch === '"') {
        const next = s[i + 1];
        if (next === '"') {
          cur += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cur += ch;
      }
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
      continue;
    }

    if (ch === ",") {
      row.push(cur);
      cur = "";
      continue;
    }

    if (ch === "\n") {
      row.push(cur);
      cur = "";
      rowsRaw.push(row);
      row = [];
      continue;
    }

    cur += ch;
  }

  row.push(cur);
  rowsRaw.push(row);

  while (rowsRaw.length && rowsRaw[rowsRaw.length - 1].every((v) => (v ?? "").trim() === "")) rowsRaw.pop();

  const headers = (rowsRaw[0] ?? []).map((h) => (h ?? "").toString().trim());
  const data = rowsRaw.slice(1);

  const rows = data.map((arr) => {
    const r: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) r[headers[i] || `Column${i + 1}`] = (arr[i] ?? "").toString();
    return r;
  });

  return { headers, rows };
}

function compareCsv(
  leftCsv: string,
  rightCsv: string
): { summary: string; onlyInLeft: Record<string, any>[]; onlyInRight: Record<string, any>[]; headers: string[] } {
  const L = parseCsvText(leftCsv);
  const R = parseCsvText(rightCsv);

  const leftHeaders = L.headers.filter(Boolean);
  const rightHeaders = R.headers.filter(Boolean);

  const commonHeaders = leftHeaders.filter((h) => rightHeaders.includes(h));
  const headerNote =
    leftHeaders.join("|") === rightHeaders.join("|")
      ? "Headers match."
      : `Headers differ. Comparing on common headers: ${commonHeaders.length}/${Math.max(leftHeaders.length, rightHeaders.length)}.`;

  const headersForKey = commonHeaders.length ? commonHeaders : makeUniqueHeaders([...leftHeaders, ...rightHeaders]);

  const keyOf = (row: Record<string, any>) =>
    headersForKey.map((h) => (row[h] ?? "").toString().trim()).join("\u241F");

  const leftCounts = new Map<string, number>();
  const rightCounts = new Map<string, number>();

  for (const r of L.rows) {
    const k = keyOf(r);
    leftCounts.set(k, (leftCounts.get(k) ?? 0) + 1);
  }
  for (const r of R.rows) {
    const k = keyOf(r);
    rightCounts.set(k, (rightCounts.get(k) ?? 0) + 1);
  }

  const onlyInLeft: Record<string, any>[] = [];
  const onlyInRight: Record<string, any>[] = [];

  for (const r of L.rows) {
    const k = keyOf(r);
    const lc = leftCounts.get(k) ?? 0;
    const rc = rightCounts.get(k) ?? 0;
    if (lc > rc) {
      onlyInLeft.push(r);
      leftCounts.set(k, lc - 1);
    }
  }
  for (const r of R.rows) {
    const k = keyOf(r);
    const lc = leftCounts.get(k) ?? 0;
    const rc = rightCounts.get(k) ?? 0;
    if (rc > lc) {
      onlyInRight.push(r);
      rightCounts.set(k, rc - 1);
    }
  }

  const summary =
    `Compare result:\n` +
    `- Generated rows: ${L.rows.length}\n` +
    `- Other rows: ${R.rows.length}\n` +
    `- Only in generated: ${onlyInLeft.length}\n` +
    `- Only in other: ${onlyInRight.length}\n` +
    `- ${headerNote}`;

  return { summary, onlyInLeft, onlyInRight, headers: headersForKey };
}

// ---------- filter evaluation ----------
function tryParseNumber(s: string): number | null {
  const t = (s ?? "").trim();
  if (!t) return null;
  const normalized = t.replace(/,/g, "");
  const n = Number(normalized);
  return Number.isFinite(n) ? n : null;
}

function tryParseDateMs(s: string): number | null {
  const t = (s ?? "").trim();
  if (!t) return null;
  const ms = Date.parse(t);
  return Number.isFinite(ms) ? ms : null;
}

function compareForLtGt(aRaw: string, bRaw: string): number | null {
  const a = (aRaw ?? "").trim();
  const b = (bRaw ?? "").trim();
  if (!a || !b) return null;

  const an = tryParseNumber(a);
  const bn = tryParseNumber(b);
  if (an !== null && bn !== null) return an === bn ? 0 : an < bn ? -1 : 1;

  const ad = tryParseDateMs(a);
  const bd = tryParseDateMs(b);
  if (ad !== null && bd !== null) return ad === bd ? 0 : ad < bd ? -1 : 1;

  const cmp = a.localeCompare(b);
  return cmp === 0 ? 0 : cmp < 0 ? -1 : 1;
}



function isNegOp(op: FilterOp) {
  return op === "neq" || op === "notLike";
}

/**
 * Auto alignment:
 * ✅ Single-cell ranges must align (no global fallback)
 */
function sheetValuesAuto(record: Record<string, any>, f: FilterCondition, grid: Grid): string[] {
  const a1 = (f.sheetRangeA1 ?? "").trim();
  const parsed = parseA1Range(a1);
  if (!parsed) return [];

  const rng = normalizeRange(parsed, grid);

  const rowIdx = typeof record.__sheetRow === "number" ? (record.__sheetRow as number) : null;
  const colIdx = typeof record.__sheetCol === "number" ? (record.__sheetCol as number) : null;

  const inRange = (r: number, c: number) => r >= rng.r0 && r <= rng.r1 && c >= rng.c0 && c <= rng.c1;

  const isSingleCol = rng.c0 === rng.c1;
  const isSingleRow = rng.r0 === rng.r1;
  const isSingleCell = isSingleRow && isSingleCol;

  // single-cell: must align
  if (isSingleCell) {
    if (rowIdx !== null && colIdx !== null && inRange(rowIdx, colIdx)) {
      return [(grid[rowIdx]?.[colIdx] ?? "").toString()];
    }
    return [];
  }

  // 1) both coords + inside range => single cell
  if (rowIdx !== null && colIdx !== null && inRange(rowIdx, colIdx)) {
    return [(grid[rowIdx]?.[colIdx] ?? "").toString()];
  }

  // 2) single column + row => cell
  if (isSingleCol && rowIdx !== null && rowIdx >= rng.r0 && rowIdx <= rng.r1) {
    return [(grid[rowIdx]?.[rng.c0] ?? "").toString()];
  }

  // 3) single row + col => cell
  if (isSingleRow && colIdx !== null && colIdx >= rng.c0 && colIdx <= rng.c1) {
    return [(grid[rng.r0]?.[colIdx] ?? "").toString()];
  }

  // 4) row slice
  if (rowIdx !== null && rowIdx >= rng.r0 && rowIdx <= rng.r1) {
    const vals: string[] = [];
    for (let c = rng.c0; c <= rng.c1; c++) vals.push((grid[rowIdx]?.[c] ?? "").toString());
    return vals;
  }

  // 5) col slice
  if (colIdx !== null && colIdx >= rng.c0 && colIdx <= rng.c1) {
    const vals: string[] = [];
    for (let r = rng.r0; r <= rng.r1; r++) vals.push((grid[r]?.[colIdx] ?? "").toString());
    return vals;
  }

  // 6) fallback: all cells
  return getRange2D(grid, rng).flat().map((v) => (v ?? "").toString());
}

function passesFilters(record: Record<string, any>, filters: FilterCondition[], grid: Grid) {
  for (const f of filters) {
    const right = (f.value ?? "").toString();
    const neg = isNegOp(f.op);

    let leftValues: string[] = [];

    if (f.source === "output") {
      const field = (f.field ?? "").toString();
      leftValues = [((record[field] ?? "") as any).toString()];
    } else {
      leftValues = sheetValuesAuto(record, f, grid);
    }

    if (leftValues.length === 0) {
      if (!neg) return false;
      continue;
    }

    if (f.op === "isEmpty" || f.op === "isNotEmpty") {
      const ok = leftValues.some((lv) => evalOp(lv, f.op, ""));
      if (!ok) return false;
      continue;
    }

if (!neg) {
  const ok = leftValues.some((lv) => evalOp(lv, f.op, right));
  if (!ok) return false;
} else {
  const ok = leftValues.every((lv) => evalOp(lv, f.op, right));
  if (!ok) return false;
}
  }
  return true;
}

function applyFiltersToRows(rows: Record<string, any>[], filters: FilterCondition[], grid: Grid) {
  if (!filters.length) return rows;
  return rows.filter((r) => passesFilters(r, filters, grid));
}

function findDuplicates(rows: Record<string, any>[], headers: string[]) {
  const keyOf = (r: Record<string, any>) => headers.map((h) => (r[h] ?? "").toString().trim()).join("\u241F");
  const counts = new Map<string, number>();
  for (const r of rows) {
    const k = keyOf(r);
    counts.set(k, (counts.get(k) ?? 0) + 1);
  }

  const duplicateRows: Record<string, any>[] = [];
  for (const r of rows) {
    const k = keyOf(r);
    if ((counts.get(k) ?? 0) > 1) duplicateRows.push(r);
  }

  const groups = Array.from(counts.values()).filter((n) => n > 1).length;
  return { groups, dupRowCount: duplicateRows.length, duplicateRows };
}

// ---------- Filters UI ----------
type FiltersBlockProps = {
  which: Mode;
  filters: FilterCondition[];
  setFilters: React.Dispatch<React.SetStateAction<FilterCondition[]>>;
  outputFields: string[];
  onAddFilter: (which: Mode) => void;
  onClear: (which: Mode) => void;
  opLabel: Record<FilterOp, string>;
  muted: React.CSSProperties;
  inputStyle: React.CSSProperties;
  btnStyle: (variant?: "primary" | "ghost") => React.CSSProperties;
  tokens: {
    border: string;
    surface: string;
    surface2: string;
    text: string;
    muted: string;
    primary: string;
    onPrimary: string;
  };
};
function isEmptyValue(s: string) {
  return (s ?? "").toString().trim() === "";
}


function evalOp(left: string, op: FilterOp, right: string) {
  const L = (left ?? "").toString();
  const R = (right ?? "").toString();

  switch (op) {
    case "isEmpty":
      return isEmptyValue(L);
    case "isNotEmpty":
      return !isEmptyValue(L);

    case "eq":
      return L.trim() === R.trim();
    case "neq":
      return L.trim() !== R.trim();
    case "like":
      return L.toLowerCase().includes(R.toLowerCase());
    case "notLike":
      return !L.toLowerCase().includes(R.toLowerCase());
    case "lt": {
      const cmp = compareForLtGt(L, R);
      return cmp !== null && cmp < 0;
    }
    case "gt": {
      const cmp = compareForLtGt(L, R);
      return cmp !== null && cmp > 0;
    }
    default:
      return false;
  }
}

const FiltersBlock = React.memo(function FiltersBlock(props: FiltersBlockProps) {
  const { which, filters, setFilters, outputFields, onAddFilter, onClear, opLabel, muted, inputStyle, btnStyle, tokens } = props;

  return (
    <div style={{ borderTop: `1px solid ${tokens.border}`, paddingTop: 14, marginTop: 14 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div style={{ fontWeight: 800 }}>Filters</div>
        <div style={{ ...muted, fontSize: 13 }}>Output column OR Sheet range (Auto).</div>
        <div style={{ marginLeft: "auto", display: "flex", gap: 8 }}>
          <button style={btnStyle("ghost")} onClick={() => onAddFilter(which)}>
            + Add filter
          </button>
          <button style={btnStyle("ghost")} onClick={() => onClear(which)} disabled={!filters.length}>
            Clear
          </button>
        </div>
      </div>

      {filters.length === 0 ? (
        <div style={{ marginTop: 10, ...muted, fontSize: 13 }}>No filters added.</div>
      ) : (
        <div style={{ marginTop: 12, display: "grid", gap: 10 }}>
          {filters.map((f) => (
            <div
              key={f.id}
              style={{
                border: `1px solid ${tokens.border}`,
                borderRadius: 14,
                padding: 12,
                background: tokens.surface2,
              }}
            >
              <div style={{ display: "grid", gridTemplateColumns: "170px 1fr auto", gap: 10, alignItems: "center" }}>
                <select
                  style={inputStyle}
                  value={f.source}
                  onChange={(e) => {
                    const source = e.target.value as FilterSource;
                    setFilters((prev) =>
                      prev.map((x) => {
                        if (x.id !== f.id) return x;
                        if (source === "output") return { ...x, source, field: x.field ?? outputFields[0] ?? "" };
                        return { ...x, source, sheetRangeA1: x.sheetRangeA1 ?? "" };
                      })
                    );
                  }}
                >
                  <option value="output">Output column</option>
                  <option value="sheet">Sheet range</option>
                </select>

                <div style={{ ...muted, fontSize: 12 }}>
                  {f.source === "output"
                    ? "Compare produced CSV column value."
                    : "Compare against sheet A1 range (Auto aligns by cell/row/col when possible)."}
                </div>

                <button style={btnStyle("ghost")} onClick={() => setFilters((prev) => prev.filter((x) => x.id !== f.id))}>
                  Remove
                </button>
              </div>

              <div
                style={{
                  marginTop: 12,
                  display: "grid",
                  gridTemplateColumns: "1fr 140px 1fr",
                  gap: 10,
                  alignItems: "center",
                }}
              >
                {f.source === "output" ? (
                  <select
                    style={inputStyle}
                    value={f.field ?? ""}
                    onChange={(e) => setFilters((prev) => prev.map((x) => (x.id === f.id ? { ...x, field: e.target.value } : x)))}
                  >
                    {outputFields.length ? (
                      outputFields.map((h) => (
                        <option key={h} value={h}>
                          {h}
                        </option>
                      ))
                    ) : (
                      <option value="">(No output fields)</option>
                    )}
                  </select>
                ) : (
                  <input
                    style={inputStyle}
                    placeholder="A1 range (e.g. C13:C50)"
                    value={f.sheetRangeA1 ?? ""}
                    onChange={(e) => setFilters((prev) => prev.map((x) => (x.id === f.id ? { ...x, sheetRangeA1: e.target.value } : x)))}
                  />
                )}

                <select
                  style={inputStyle}
                  value={f.op}
                  onChange={(e) => setFilters((prev) => prev.map((x) => (x.id === f.id ? { ...x, op: e.target.value as FilterOp } : x)))}
                >
                  {(["eq", "neq", "lt", "gt", "like", "notLike", "isEmpty", "isNotEmpty"] as FilterOp[]).map((op) => (
                    <option key={op} value={op}>
                      {opLabel[op]}
                    </option>
                  ))}
                </select>

              <input
                style={inputStyle}
                placeholder="compare value…"
                value={f.value}
                disabled={f.op === "isEmpty" || f.op === "isNotEmpty"}
                onChange={(e) => setFilters((prev) => prev.map((x) => (x.id === f.id ? { ...x, value: e.target.value } : x)))}
              />
              </div>

              
            </div>
          ))}
        </div>
      )}

      <div style={{ marginTop: 10, ...muted, fontSize: 12 }}>
        Notes: <code>{"<"}</code>/<code>{">"}</code> try number/date compare; <code>like</code> is case-insensitive contains.
      </div>
    </div>
  );
});

// ---------- component ----------
export default function ExcelSmartParserPage() {
  const [step, setStep] = useState<Step>(0);
  const [compareSummary, setCompareSummary] = useState<string>("");
  const [compareReportTxt, setCompareReportTxt] = useState<string>("");



  const [workbook, setWorkbook] = useState<XLSX.WorkBook | null>(null);
  const [sheetName, setSheetName] = useState<string>("");
  const [grid, setGrid] = useState<Grid>([]);

  const [mode, setMode] = useState<Mode>("roles");

  // Records config (formerly Roles)
  const [rolesColumns, setRolesColumns] = useState<RolesColumnSpec[]>([{ header: "RoleName", rangesA1: [""] }]);
  const [requiredRoleHeader, setRequiredRoleHeader] = useState<string>("RoleName");
  const [rolesCsv, setRolesCsv] = useState<string>("");
  const [rolesWarnings, setRolesWarnings] = useState<string[]>([]);
  const [rolesDupCsv, setRolesDupCsv] = useState<string>("");

  // Assignments config
  const [assignAHeader, setAssignAHeader] = useState<string>("RoleName");
  const [assignBHeader, setAssignBHeader] = useState<string>("EntitlementName");
  const [assignObjARange, setAssignObjARange] = useState<string>("");
  const [assignObjBRange, setAssignObjBRange] = useState<string>("");
  const [assignMatrixRange, setAssignMatrixRange] = useState<string>("");
  const [assignMarkValues, setAssignMarkValues] = useState<string>("1,X,x,YES,yes");

  // ✅ NEW: optional extra assignment columns
  const [assignExtraColumns, setAssignExtraColumns] = useState<AssignExtraColumnSpec[]>([]);

  const [assignCsv, setAssignCsv] = useState<string>("");
  const [assignWarnings, setAssignWarnings] = useState<string[]>([]);
  const [assignDupCsv, setAssignDupCsv] = useState<string>("");

  // Filters (per mode)
  const [rolesFilters, setRolesFilters] = useState<FilterCondition[]>([]);
  const [assignFilters, setAssignFilters] = useState<FilterCondition[]>([]);

  const sheets = useMemo(() => workbook?.SheetNames ?? [], [workbook]);

  const templateImportRef = useRef<HTMLInputElement | null>(null);
  const templateSheetToLoadRef = useRef<string>("");
  const compareCsvRef = useRef<HTMLInputElement | null>(null);

  function buildTemplate(): TemplateV1 {
    return {
      version: 1,
      mode,
      rolesColumns,
      requiredRoleHeader,
      rolesFilters,
      assignAHeader,
      assignBHeader,
      assignObjARange,
      assignObjBRange,
      assignMatrixRange,
      assignMarkValues,
      assignExtraColumns,
      assignFilters,
      sheetName: sheetName || undefined,
    };
  }

  function applyTemplate(t: Partial<TemplateV1>) {
    // Only apply known fields; ignore anything else (forward-compatible)
    if (t.mode === "roles" || t.mode === "assignments") setMode(t.mode);

    if (Array.isArray(t.rolesColumns)) setRolesColumns(t.rolesColumns as any);
    if (typeof t.requiredRoleHeader === "string") setRequiredRoleHeader(t.requiredRoleHeader);
    if (Array.isArray(t.rolesFilters)) setRolesFilters(t.rolesFilters as any);

    if (typeof t.assignAHeader === "string") setAssignAHeader(t.assignAHeader);
    if (typeof t.assignBHeader === "string") setAssignBHeader(t.assignBHeader);
    if (typeof t.assignObjARange === "string") setAssignObjARange(t.assignObjARange);
    if (typeof t.assignObjBRange === "string") setAssignObjBRange(t.assignObjBRange);
    if (typeof t.assignMatrixRange === "string") setAssignMatrixRange(t.assignMatrixRange);
    if (typeof t.assignMarkValues === "string") setAssignMarkValues(t.assignMarkValues);
    if (Array.isArray(t.assignExtraColumns)) setAssignExtraColumns(t.assignExtraColumns as any);
    if (Array.isArray(t.assignFilters)) setAssignFilters(t.assignFilters as any);

    if (typeof t.sheetName === "string") {
      templateSheetToLoadRef.current = t.sheetName;
      if (workbook && workbook.SheetNames?.includes(t.sheetName)) {
        loadSheet(workbook, t.sheetName);
      }
    }

    // Clear generated outputs (keep workbook/grid intact if already loaded)
    setRolesCsv("");
    setAssignCsv("");
    setRolesWarnings([]);
    setAssignWarnings([]);
    setRolesDupCsv("");
    setAssignDupCsv("");
    setCompareSummary("");
    setCompareReportTxt("");

  }

  function onImportTemplate(file: File) {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const raw = (e.target?.result ?? "").toString();
        const parsed = JSON.parse(raw) as Partial<TemplateV1>;
        applyTemplate(parsed);
      } catch (err) {
        console.error("Template import failed", err);
        alert("Could not import template JSON. Please verify the file.");
      }
    };
    reader.readAsText(file);
  }

  function onSaveTemplate() {
    const t = buildTemplate();
    downloadJson("excel-smart-parser.template.json", t);
  }


  function loadSheet(wb: XLSX.WorkBook, name: string) {
    const ws = wb.Sheets[name];
    const ref = (ws as any)["!ref"] as string | undefined;

    // Force range to start at A1
    const decoded = ref ? XLSX.utils.decode_range(ref) : { s: { r: 0, c: 0 }, e: { r: 0, c: 0 } };
    const forcedRange = { s: { r: 0, c: 0 }, e: { r: decoded.e.r, c: decoded.e.c } };

    const rows = XLSX.utils.sheet_to_json(ws, {
      header: 1,
      raw: false,
      defval: "",
      range: forcedRange,
    }) as any[][];

    const maxCols = rows.reduce((m, r) => Math.max(m, r.length), 0);
    const normalized: Grid = rows.map((r) => {
      const rr = r.map((v) => (v ?? "").toString());
      while (rr.length < maxCols) rr.push("");
      return rr;
    });

    // Fill merged cells
    const merges =
      (ws as any)["!merges"] as Array<{ s: { r: number; c: number }; e: { r: number; c: number } }> | undefined;
    if (merges?.length) {
      for (const m of merges) {
        const v = normalized[m.s.r]?.[m.s.c] ?? "";
        for (let r = m.s.r; r <= m.e.r; r++) {
          for (let c = m.s.c; c <= m.e.c; c++) {
            if ((normalized[r]?.[c] ?? "") === "") normalized[r][c] = v;
          }
        }
      }
    }

    setGrid(normalized);
    setSheetName(name);

    setRolesCsv("");
    setAssignCsv("");
    setRolesWarnings([]);
    setAssignWarnings([]);
    setRolesDupCsv("");
    setAssignDupCsv("");
    setCompareSummary("");
    setCompareReportTxt("");

  }

  function onFile(file: File) {
    const reader = new FileReader();
    reader.onload = (e) => {
      const data = e.target?.result;
      if (!data) return;
      const wb = XLSX.read(data, { type: "array" });
      setWorkbook(wb);

      const first = wb.SheetNames[0] ?? "";
      const desired = (templateSheetToLoadRef.current ?? "").trim();
      const toLoad = desired && wb.SheetNames.includes(desired) ? desired : first;
      setSheetName("");
      setGrid([]);

      if (toLoad) {
        loadSheet(wb, toLoad);
        setStep(1);
      } else {
        setStep(0);
      }
    };
    reader.readAsArrayBuffer(file);
  }


  function onCompareCsvFile(file: File) {
  const current = mode === "roles" ? rolesCsv : assignCsv;
  if (!current) {
    alert("Generate a CSV first, then compare.");
    return;
  }

  const reader = new FileReader();
  reader.onload = (e) => {
    const other = (e.target?.result ?? "").toString();
    const res = compareCsv(current, other);

    // Build a readable TXT report
    const maxList = 200; // keep it readable; adjust if you want
    const onlyLeftSample = res.onlyInLeft.slice(0, maxList);
    const onlyRightSample = res.onlyInRight.slice(0, maxList);

    const renderRow = (r: Record<string, any>) =>
      res.headers.map((h: string | number) => `${h}=${(r[h] ?? "").toString().trim()}`).join(" | ");

    const lines: string[] = [];
    lines.push("CSV Comparison Report");
    lines.push("=====================");
    lines.push("");
    lines.push(res.summary);
    lines.push("");
    lines.push(`Headers used for compare (${res.headers.length}):`);
    lines.push(res.headers.join(", "));
    lines.push("");

    lines.push(`Only in GENERATED (${res.onlyInLeft.length})`);
    lines.push("----------------------");
    if (res.onlyInLeft.length === 0) lines.push("(none)");
    else onlyLeftSample.forEach((r: Record<string, any>, i: number) => lines.push(`${i + 1}. ${renderRow(r)}`));
    if (res.onlyInLeft.length > maxList) lines.push(`... truncated (${res.onlyInLeft.length - maxList} more)`);
    lines.push("");

    lines.push(`Only in OTHER CSV (${res.onlyInRight.length})`);
    lines.push("-------------------");
    if (res.onlyInRight.length === 0) lines.push("(none)");
    else onlyRightSample.forEach((r, i) => lines.push(`${i + 1}. ${renderRow(r)}`));
    if (res.onlyInRight.length > maxList) lines.push(`... truncated (${res.onlyInRight.length - maxList} more)`);
    lines.push("");

    const report = lines.join("\n");

    setCompareSummary(res.summary);
    setCompareReportTxt(report);
  };
  reader.readAsText(file);
}

  const rolesOutputFields = useMemo(() => rolesColumns.map((c) => c.header.trim()).filter(Boolean), [rolesColumns]);

  const assignmentsHeadersUnique = useMemo(() => {
    const base = [assignAHeader.trim() || "ObjectA", assignBHeader.trim() || "ObjectB"];
    const extras = assignExtraColumns.map((c) => c.header.trim()).filter(Boolean);
    return makeUniqueHeaders([...base, ...extras]);
  }, [assignAHeader, assignBHeader, assignExtraColumns]);

  const assignOutputFields = useMemo(() => assignmentsHeadersUnique, [assignmentsHeadersUnique]);

  const opLabel: Record<FilterOp, string> = {
  eq: "=",
  neq: "!=",
  lt: "<",
  gt: ">",
  like: "like",
  notLike: "not like",
  isEmpty: "is empty",
  isNotEmpty: "is not empty",
};

  function addFilter(which: Mode) {
    const base: FilterCondition = {
      id: uid(),
      source: "output",
      field: "",
      sheetRangeA1: "",
      op: "like",
      value: "",
    };

    if (which === "roles") {
      const defaultField = rolesOutputFields[0] ?? "";
      setRolesFilters((prev) => [...prev, { ...base, field: defaultField }]);
    } else {
      const defaultField = assignOutputFields[0] ?? "";
      setAssignFilters((prev) => [...prev, { ...base, field: defaultField }]);
    }
  }

  function clearFilters(which: Mode) {
    if (which === "roles") setRolesFilters([]);
    else setAssignFilters([]);
  }

  const canGoNext = useMemo(() => {
    if (step === 0) return !!workbook;
    if (step === 1) return !!workbook && !!sheetName && grid.length > 0;

    if (step === 2) {
      if (mode === "roles") return rolesColumns.some((c) => c.header.trim());
      return assignAHeader.trim() !== "" && assignBHeader.trim() !== "";
    }

    if (step === 3) {
      if (mode === "roles") return rolesColumns.some((c) => c.rangesA1.some((r) => r.trim() !== ""));
      return assignObjARange.trim() !== "" && assignObjBRange.trim() !== "" && assignMatrixRange.trim() !== "";
    }

    return true;
  }, [
    step,
    workbook,
    sheetName,
    grid.length,
    mode,
    rolesColumns,
    assignAHeader,
    assignBHeader,
    assignObjARange,
    assignObjBRange,
    assignMatrixRange,
  ]);

  function generateRecordsCsv() {
    if (!grid.length) return;

    const headersRaw = rolesColumns.map((c) => c.header.trim()).filter(Boolean);
    const headers = makeUniqueHeaders(headersRaw);
    const warnings: string[] = [];

    if (!headers.length) {
      setRolesCsv("");
      setRolesWarnings(["No headers defined."]);
      setRolesDupCsv("");
      return;
    }

    // Map from user headersRaw -> unique headers
    const headerMap = new Map<string, string>();
    for (let i = 0; i < headersRaw.length; i++) headerMap.set(headersRaw[i], headers[i]);

    const colMaps: Record<string, Map<RoleKey, string>> = {};
    const allKeys = new Set<RoleKey>();

    for (const col of rolesColumns) {
      const userHeader = col.header.trim();
      if (!userHeader) continue;
      const outHeader = headerMap.get(userHeader) ?? userHeader;

      const merged = new Map<RoleKey, string>();
      let headerKeyKind: "row" | "col" | null = null;

      for (const a1 of col.rangesA1) {
        const t = a1.trim();
        if (!t) continue;

        const parsed = parseA1Range(t);
        if (!parsed) {
          warnings.push(`Invalid range for "${outHeader}": "${t}"`);
          continue;
        }

        const { map, warning, keyKind } = getRolesMap(grid, parsed);
        if (warning) warnings.push(`"${outHeader}" (${t}): ${warning}`);

        if (headerKeyKind && headerKeyKind !== keyKind) {
          warnings.push(`"${outHeader}": mixed orientations across ranges (row-based + col-based). Results will be combined.`);
        }
        headerKeyKind = headerKeyKind ?? keyKind;

        for (const [k, v] of map.entries()) merged.set(k, v);
      }

      colMaps[outHeader] = merged;
      for (const k of merged.keys()) allKeys.add(k);
    }

    const sortedKeys = Array.from(allKeys).sort((a, b) => {
      const pa = parseRoleKey(a);
      const pb = parseRoleKey(b);
      if (!pa || !pb) return a.localeCompare(b);
      if (pa.kind !== pb.kind) return pa.kind === "row" ? -1 : 1;
      return pa.idx - pb.idx;
    });

    const reqUser = requiredRoleHeader.trim();
    const reqOut = reqUser ? headerMap.get(reqUser) ?? reqUser : "";
    const useRequired = reqOut !== "" && headers.includes(reqOut);

    const rows: Record<string, any>[] = [];
    let producedRowKeys = 0;
    let producedColKeys = 0;

    for (const k of sortedKeys) {
      const record: Record<string, any> = {};

      const pk = parseRoleKey(k);
      if (pk?.kind === "row") {
        record.__sheetRow = pk.idx;
        producedRowKeys++;
      }
      if (pk?.kind === "col") {
        record.__sheetCol = pk.idx;
        producedColKeys++;
      }

      for (const h of headers) record[h] = colMaps[h]?.get(k) ?? "";

      const hasAny = Object.entries(record)
        .filter(([kk]) => kk !== "__sheetRow" && kk !== "__sheetCol")
        .some(([, v]) => (v ?? "").toString().trim() !== "");
      if (!hasAny) continue;

      if (useRequired && (record[reqOut] ?? "").toString().trim() === "") continue;

      rows.push(record);
    }

    const filtered = applyFiltersToRows(rows, rolesFilters, grid);

    const isColumnBased = producedColKeys > 0 && producedColKeys >= producedRowKeys;
    if (rolesFilters.length) {
      warnings.push(`Filters applied: kept ${filtered.length}/${rows.length} ${isColumnBased ? "columns" : "rows"}.`);
    }

    const { groups, dupRowCount, duplicateRows } = findDuplicates(filtered, headers);
    if (dupRowCount > 0) {
      warnings.push(`Duplicates found: ${dupRowCount} rows in ${groups} duplicate group(s).`);
      setRolesDupCsv(toCsv(headers, duplicateRows));
    } else {
      setRolesDupCsv("");
      warnings.push("Duplicates found: 0");
    }

    setRolesWarnings(warnings);
    setRolesCsv(toCsv(headers, filtered));
  }

  // helper to compute an "auto" value for a record from an A1 range (single value output)
  function autoValueForRange(record: Record<string, any>, rangeA1: string): string {
    const vals = sheetValuesAuto(record, {
      id: "tmp", source: "sheet", sheetRangeA1: rangeA1, op: "like", value: "",
      field: ""
    }, grid);
    const cleaned = vals.map((v) => (v ?? "").toString().trim()).filter(Boolean);
    if (!cleaned.length) return "";
    if (cleaned.length === 1) return cleaned[0];
    return cleaned.join(" ");
  }

  function autoValueForRanges(record: Record<string, any>, rangesA1: string[]): string {
    const parts: string[] = [];
    for (const r of rangesA1) {
      const t = (r ?? "").trim();
      if (!t) continue;
      const v = autoValueForRange(record, t);
      if (v) parts.push(v);
    }
    if (!parts.length) return "";
    if (parts.length === 1) return parts[0];
    return parts.join(" ");
  }

  function generateAssignmentsCsv() {
    if (!grid.length) return;

    const warnings: string[] = [];
    const aR0 = parseA1Range(assignObjARange);
    const bR0 = parseA1Range(assignObjBRange);
    const mR0 = parseA1Range(assignMatrixRange);

    if (!aR0 || !bR0 || !mR0) {
      setAssignCsv("");
      setAssignWarnings(["Please provide valid ranges for Object A, Object B, and Matrix."]);
      setAssignDupCsv("");
      return;
    }

    const objAR = normalizeRange(aR0, grid);
    const objBR = normalizeRange(bR0, grid);
    const matR = normalizeRange(mR0, grid);

    const objAisVertical = objAR.c0 === objAR.c1;
    const objAisHorizontal = objAR.r0 === objAR.r1;
    const objBisVertical = objBR.c0 === objBR.c1;
    const objBisHorizontal = objBR.r0 === objBR.r1;

    if (!(objAisVertical || objAisHorizontal)) warnings.push("Object A range must be a single column or single row.");
    if (!(objBisVertical || objBisHorizontal)) warnings.push("Object B range must be a single column or single row.");
    if (warnings.length) {
      setAssignWarnings(warnings);
      setAssignCsv("");
      setAssignDupCsv("");
      return;
    }

    const objA = getRangeVector(grid, objAR).map((v) => (v ?? "").toString().trim());
    const objB = getRangeVector(grid, objBR).map((v) => (v ?? "").toString().trim());
    const matrix = getRange2D(grid, matR).map((row) => row.map((v) => (v ?? "").toString().trim()));

    const marks = assignMarkValues
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    const markSet = new Set(marks.map((m) => m.toLowerCase()));

    // Build headers (unique)
    const baseHeadersRaw = [assignAHeader.trim() || "ObjectA", assignBHeader.trim() || "ObjectB"];
    const extraHeadersRaw = assignExtraColumns.map((c) => c.header.trim()).filter(Boolean);
    const allHeadersUnique = makeUniqueHeaders([...baseHeadersRaw, ...extraHeadersRaw]);

    const baseAHeader = allHeadersUnique[0];
    const baseBHeader = allHeadersUnique[1];
    const extraHeadersUnique = allHeadersUnique.slice(2);

    const outRows: Record<string, any>[] = [];

    let totalMarked = 0;
    let emitted = 0;
    let skippedOutOfBounds = 0;
    let skippedMissingA = 0;
    let skippedMissingB = 0;

    for (let i = 0; i < matrix.length; i++) {
      for (let j = 0; j < (matrix[i]?.length ?? 0); j++) {
        const cell = (matrix[i][j] ?? "").trim();
        if (!cell) continue;
        if (!markSet.has(cell.toLowerCase())) continue;

        totalMarked++;

        const absRow = matR.r0 + i;
        const absCol = matR.c0 + j;

        const idxA = objAisVertical ? absRow - objAR.r0 : absCol - objAR.c0;
        const idxB = objBisHorizontal ? absCol - objBR.c0 : absRow - objBR.r0;

        if (idxA < 0 || idxA >= objA.length || idxB < 0 || idxB >= objB.length) {
          skippedOutOfBounds++;
          continue;
        }

        const left = (objA[idxA] ?? "").trim();
        const right = (objB[idxB] ?? "").trim();

        if (!left) {
          skippedMissingA++;
          continue;
        }
        if (!right) {
          skippedMissingB++;
          continue;
        }

        const record: Record<string, any> = {
          [baseAHeader]: left,
          [baseBHeader]: right,
          __sheetRow: absRow,
          __sheetCol: absCol,
        };

        // ✅ NEW: add optional extra columns from their ranges
        // alignment uses record.__sheetRow/__sheetCol with Auto
        for (let k = 0; k < assignExtraColumns.length; k++) {
          const spec = assignExtraColumns[k];
          const userH = spec.header.trim();
          if (!userH) continue;

          const outH = extraHeadersUnique[k]; // corresponds to the kth non-empty header in order
          if (!outH) continue;

          record[outH] = autoValueForRanges(record, spec.rangesA1);
        }

        outRows.push(record);
        emitted++;
      }
    }

    warnings.push(
      `Marks found: ${totalMarked}, emitted: ${emitted}, skippedOutOfBounds: ${skippedOutOfBounds}, skippedMissingA: ${skippedMissingA}, skippedMissingB: ${skippedMissingB}`
    );

    if (!outRows.length) warnings.push("No assignments found. Check mark values and ranges.");

    const filtered = applyFiltersToRows(outRows, assignFilters, grid);
    if (assignFilters.length) warnings.push(`Filters applied: kept ${filtered.length}/${outRows.length} rows.`);

    const { groups, dupRowCount, duplicateRows } = findDuplicates(filtered, allHeadersUnique);
    if (dupRowCount > 0) {
      warnings.push(`Duplicates found: ${dupRowCount} rows in ${groups} duplicate group(s).`);
      setAssignDupCsv(toCsv(allHeadersUnique, duplicateRows));
    } else {
      setAssignDupCsv("");
      warnings.push("Duplicates found: 0");
    }

    setAssignWarnings(warnings);
    setAssignCsv(toCsv(allHeadersUnique, filtered));
  }

  // ---------- UI styles ----------
  // Intragen-ish palette (colors only; layout/logic unchanged)
  const tokens = {
    bg: "#f2ece2",
    panel: "#ffffff",
    border: "#e0dad2",
    text: "#1c2020",
    muted: "#5f5a57",
    primary: "#834078",
    onPrimary: "#ffffff",
    shadow: "0 1px 2px rgba(0,0,0,0.04), 0 8px 24px rgba(0,0,0,0.06)",
    radius: 16,
    surface: "#ffffff",
    surface2: "#f7f2e8",
    warnBg: "#fff7e6",
    warnBorder: "#f0d7a6",
    codeBg: "#0b0b0b",
    codeText: "#f2f2f2",
  };


  const page: React.CSSProperties = {
    minHeight: "100vh",
    background: tokens.bg,
    color: tokens.text,
    fontFamily: "ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial",
  };

  const container: React.CSSProperties = {
    maxWidth: 980,
    margin: "0 auto",
    padding: "28px 16px 48px",
  };

  const headerRow: React.CSSProperties = {
    display: "flex",
    alignItems: "flex-end",
    justifyContent: "space-between",
    gap: 16,
    marginBottom: 14,
  };

  const h1: React.CSSProperties = { margin: 0, fontSize: 20, letterSpacing: -0.2 };
  const sub: React.CSSProperties = { margin: "6px 0 0", color: tokens.muted, fontSize: 13 };

  const card: React.CSSProperties = {
    background: tokens.panel,
    border: `1px solid ${tokens.border}`,
    borderRadius: tokens.radius,
    boxShadow: tokens.shadow,
    padding: 18,
  };

  const muted: React.CSSProperties = { color: tokens.muted };
  const label: React.CSSProperties = { fontSize: 12, color: tokens.muted, marginBottom: 6 };

  const input: React.CSSProperties = {
    width: "100%",
    padding: "10px 12px",
    borderRadius: 12,
    border: `1px solid ${tokens.border}`,
    outline: "none",
    background: tokens.surface,
    color: tokens.text,
    fontSize: 14,
  };

  const btnStyle = (variant: "primary" | "ghost" = "ghost"): React.CSSProperties => {
    const base: React.CSSProperties = {
      padding: "10px 12px",
      borderRadius: 12,
      border: "1px solid transparent",
      cursor: "pointer",
      fontWeight: 700,
      fontSize: 13,
      lineHeight: "16px",
      userSelect: "none",
    };

    if (variant === "primary") {
      return { ...base, background: tokens.primary, color: tokens.onPrimary, borderColor: tokens.primary };
    }
    return { ...base, background: tokens.surface, color: tokens.text, borderColor: tokens.border };
  };

  const pillRow: React.CSSProperties = { display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" };
  const pill = (active: boolean): React.CSSProperties => ({
    padding: "8px 12px",
    borderRadius: 999,
    border: `1px solid ${active ? tokens.primary : tokens.border}`,
    background: active ? tokens.primary : tokens.surface,
    color: active ? tokens.onPrimary : tokens.text,
    fontWeight: 800,
    fontSize: 13,
  });

  const sectionBox = (tone: "required" | "optional"): React.CSSProperties => ({
    border: `1px solid ${tone === "required" ? tokens.border : tokens.border}`,
    borderRadius: 14,
    padding: 14,
    background: tone === "required" ? tokens.surface2 : tokens.surface,
  });

  return (
    <div style={page}>
      <div style={container}>
        <div style={headerRow}>
          <div>
            <h2 style={h1}>Excel Smart Parser → CSV Generator</h2>
            <p style={sub}>Upload → choose sheet → define output → map ranges → generate CSV.</p>
          </div>

          <div style={{ display: "flex", gap: 10 }}>
            <button
              style={{ ...btnStyle("ghost"), opacity: step === 0 ? 0.5 : 1 }}
              disabled={step === 0}
              onClick={() => setStep((s) => (s > 0 ? ((s - 1) as Step) : s))}
            >
              Back
            </button>
            <button
              style={{ ...btnStyle("primary"), opacity: canGoNext && step < 4 ? 1 : 0.5 }}
              disabled={!canGoNext || step === 4}
              onClick={() => setStep((s) => (s < 4 ? ((s + 1) as Step) : s))}
            >
              Next
            </button>
          </div>
        </div>

        <div style={pillRow}>
          {(["Upload", "Tab (Sheet)", "Define Output", "Map Ranges", "Generate"] as const).map((name, idx) => (
            <div key={name} style={pill(step === idx)}>
              {name}
            </div>
          ))}
        </div>

        <div style={{ marginTop: 14 }}>
          <div style={card}>
            {step === 0 && (
              <>
                <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 12 }}>
                  <div>
                    <h3 style={{ marginTop: 0, marginBottom: 6 }}>Upload Excel</h3>
                    <div style={{ ...muted, fontSize: 13, marginBottom: 12 }}>Upload an .xlsx / .xls / .xlsm file.</div>
                  </div>

                  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <button
                      style={btnStyle("ghost")}
                      onClick={() => templateImportRef.current?.click()}
                      title="Import a saved template JSON"
                    >
                      Import template (JSON)
                    </button>
                    <input
                      ref={templateImportRef}
                      type="file"
                      accept="application/json,.json"
                      style={{ display: "none" }}
                      onChange={(e) => {
                        const f = e.target.files?.[0];
                        if (f) onImportTemplate(f);
                        e.currentTarget.value = "";
                      }}
                    />
                  </div>
                </div>

                <div style={{ ...muted, fontSize: 12, marginTop: -6, marginBottom: 10 }}>
                  Loads previously saved mappings/filters. (Excel file is still uploaded separately.)
                </div>

                <input type="file" accept=".xlsx,.xls,.xlsm" onChange={(e) => e.target.files?.[0] && onFile(e.target.files[0])} />
              </>
            )}

            {step === 1 && (
              <>
                <h3 style={{ marginTop: 0, marginBottom: 6 }}>Select sheet</h3>
                <div style={{ ...muted, fontSize: 13, marginBottom: 12 }}>Choose which tab the parser should load data from.</div>

                {!workbook ? (
                  <div style={muted}>No workbook loaded. Go back to Upload.</div>
                ) : (
                  <>
                    <div style={label}>Sheet</div>
                    <select style={input} value={sheetName} onChange={(e) => loadSheet(workbook, e.target.value)}>
                      {sheets.map((s) => (
                        <option key={s} value={s}>
                          {s}
                        </option>
                      ))}
                    </select>

                    <div style={{ marginTop: 10, ...muted, fontSize: 13 }}>
                      Loaded: <strong style={{ color: tokens.text }}>{sheetName || "—"}</strong>
                    </div>
                  </>
                )}
              </>
            )}

            {step === 2 && (
              <>
                <h3 style={{ marginTop: 0, marginBottom: 6 }}>Define output</h3>
                <div style={{ ...muted, fontSize: 13, marginBottom: 12 }}>Pick the feature and define the CSV columns.</div>

                <div style={{ display: "flex", gap: 10 }}>
                  <button style={mode === "roles" ? btnStyle("primary") : btnStyle("ghost")} onClick={() => setMode("roles")}>
                    Records CSV
                  </button>
                  <button style={mode === "assignments" ? btnStyle("primary") : btnStyle("ghost")} onClick={() => setMode("assignments")}>
                    Assignments CSV
                  </button>
                </div>

                {mode === "roles" ? (
                  <>
                    <div style={{ marginTop: 14, ...muted, fontSize: 13 }}>
                      Define which columns should appear in the Records CSV. You’ll map ranges next.
                    </div>

                    <div style={{ marginTop: 12 }}>
                      {rolesColumns.map((c, idx) => (
                        <div key={idx} style={{ display: "grid", gridTemplateColumns: "1fr auto", gap: 10, marginBottom: 10 }}>
                          <input
                            style={input}
                            placeholder="CSV header (e.g. RoleName)"
                            value={c.header}
                            onChange={(e) => setRolesColumns((prev) => prev.map((x, i) => (i === idx ? { ...x, header: e.target.value } : x)))}
                          />
                          <button
                            style={btnStyle("ghost")}
                            onClick={() => setRolesColumns((prev) => prev.filter((_, i) => i !== idx))}
                            disabled={rolesColumns.length <= 1}
                          >
                            Remove
                          </button>
                        </div>
                      ))}
                      <button style={btnStyle("ghost")} onClick={() => setRolesColumns((prev) => [...prev, { header: "", rangesA1: [""] }])}>
                        + Add column
                      </button>

                      <div style={{ marginTop: 14 }}>
                        <div style={label}>Optional required column (missing → skipped)</div>
                        <select style={input} value={requiredRoleHeader} onChange={(e) => setRequiredRoleHeader(e.target.value)}>
                          <option value="">(None)</option>
                          {rolesColumns
                            .map((c) => c.header.trim())
                            .filter(Boolean)
                            .map((h) => (
                              <option key={h} value={h}>
                                {h}
                              </option>
                            ))}
                        </select>
                      </div>
                    </div>
                  </>
                ) : (
                  <>
                    <div style={{ marginTop: 14, ...muted, fontSize: 13 }}>
                      Define required columns (Object A / Object B) and optional extra columns. You’ll map ranges next.
                    </div>

                    <div style={{ marginTop: 12, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
                      <div>
                        <div style={label}>Output column for Object A</div>
                        <input style={input} value={assignAHeader} onChange={(e) => setAssignAHeader(e.target.value)} />
                      </div>
                      <div>
                        <div style={label}>Output column for Object B</div>
                        <input style={input} value={assignBHeader} onChange={(e) => setAssignBHeader(e.target.value)} />
                      </div>
                    </div>

                    <div style={{ marginTop: 12 }}>
                      <div style={label}>Mark values (comma-separated)</div>
                      <input style={input} value={assignMarkValues} onChange={(e) => setAssignMarkValues(e.target.value)} placeholder="e.g. 1,X,YES" />
                    </div>

                    {/* ✅ NEW: additional columns */}
                    <div style={{ marginTop: 14, ...sectionBox("optional") }}>
                      <div style={{ fontWeight: 800, marginBottom: 8 }}>Additional output columns (optional)</div>
                      <div style={{ ...muted, fontSize: 13, marginBottom: 10 }}>
                        Add extra columns to output. You’ll define their ranges in the next step.
                      </div>

                      {assignExtraColumns.length === 0 ? (
                        <div style={{ ...muted, fontSize: 13 }}>No extra columns.</div>
                      ) : (
                        <div style={{ display: "grid", gap: 10 }}>
                          {assignExtraColumns.map((c, idx) => (
                            <div key={idx} style={{ display: "grid", gridTemplateColumns: "1fr auto", gap: 10 }}>
                              <input
                                style={input}
                                placeholder="Extra column header (e.g. Department)"
                                value={c.header}
                                onChange={(e) =>
                                  setAssignExtraColumns((prev) => prev.map((x, i) => (i === idx ? { ...x, header: e.target.value } : x)))
                                }
                              />
                              <button style={btnStyle("ghost")} onClick={() => setAssignExtraColumns((prev) => prev.filter((_, i) => i !== idx))}>
                                Remove
                              </button>
                            </div>
                          ))}
                        </div>
                      )}

                      <div style={{ marginTop: 10 }}>
                        <button style={btnStyle("ghost")} onClick={() => setAssignExtraColumns((prev) => [...prev, { header: "", rangesA1: [""] }])}>
                          + Add extra column
                        </button>
                      </div>
                    </div>
                  </>
                )}
              </>
            )}

            {step === 3 && (
              <>
                <h3 style={{ marginTop: 0, marginBottom: 6 }}>Map ranges</h3>
                <div style={{ ...muted, fontSize: 13, marginBottom: 12 }}>Type ranges in A1 notation (e.g. D13:D50 or E12:AP12).</div>

                {mode === "roles" ? (
                  <>
                    {rolesColumns.map((col, ci) => (
                      <div key={ci} style={{ border: `1px solid ${tokens.border}`, borderRadius: 14, padding: 14, marginBottom: 12, background: tokens.surface }}>
                        <div style={{ fontWeight: 800, marginBottom: 10 }}>{col.header.trim() || `Column ${ci + 1}`}</div>

                        {col.rangesA1.map((r, ri) => (
                          <div key={ri} style={{ display: "grid", gridTemplateColumns: "1fr auto", gap: 10, marginBottom: 10 }}>
                            <input
                              style={input}
                              placeholder="Range (e.g. B2:B50 or E12:AP12)"
                              value={r}
                              onChange={(e) =>
                                setRolesColumns((prev) =>
                                  prev.map((x, i) => (i === ci ? { ...x, rangesA1: x.rangesA1.map((rr, j) => (j === ri ? e.target.value : rr)) } : x))
                                )
                              }
                            />
                            <button
                              style={btnStyle("ghost")}
                              disabled={col.rangesA1.length <= 1}
                              onClick={() =>
                                setRolesColumns((prev) => prev.map((x, i) => (i === ci ? { ...x, rangesA1: x.rangesA1.filter((_, j) => j !== ri) } : x)))
                              }
                            >
                              Remove
                            </button>
                          </div>
                        ))}

                        <button style={btnStyle("ghost")} onClick={() => setRolesColumns((prev) => prev.map((x, i) => (i === ci ? { ...x, rangesA1: [...x.rangesA1, ""] } : x)))}>
                          + Add range
                        </button>
                      </div>
                    ))}

                    <FiltersBlock
                      which="roles"
                      filters={rolesFilters}
                      setFilters={setRolesFilters}
                      outputFields={rolesOutputFields}
                      onAddFilter={addFilter}
                      onClear={clearFilters}
                      opLabel={opLabel}
                      muted={muted}
                      inputStyle={input}
                      btnStyle={btnStyle}
                      tokens={tokens}
                    />
                  </>
                ) : (
                  <>
                    {/* REQUIRED ranges */}
                    <div style={sectionBox("required")}>
                      <div style={{ fontWeight: 800, marginBottom: 6 }}>Required ranges</div>
                      <div style={{ ...muted, fontSize: 13, marginBottom: 12 }}>These three ranges define the assignments extraction.</div>

                      <div style={{ display: "grid", gap: 12 }}>
                        <div>
                          <div style={label}>Object A list range</div>
                          <input style={input} value={assignObjARange} onChange={(e) => setAssignObjARange(e.target.value)} placeholder="e.g. D13:D50" />
                        </div>
                        <div>
                          <div style={label}>Object B list range</div>
                          <input style={input} value={assignObjBRange} onChange={(e) => setAssignObjBRange(e.target.value)} placeholder="e.g. E12:AP12" />
                        </div>
                        <div>
                          <div style={label}>Assignment matrix range</div>
                          <input style={input} value={assignMatrixRange} onChange={(e) => setAssignMatrixRange(e.target.value)} placeholder="e.g. E13:AP50" />
                        </div>

                        <div style={{ ...muted, fontSize: 13 }}>Counts include blanks, matching Excel range dimensions.</div>
                      </div>
                    </div>

                    {/* OPTIONAL extra columns ranges */}
                    <div style={{ marginTop: 12, ...sectionBox("optional") }}>
                      <div style={{ fontWeight: 800, marginBottom: 6 }}>Additional columns ranges (optional)</div>
                      <div style={{ ...muted, fontSize: 13, marginBottom: 12 }}>
                        These ranges populate extra output columns per assignment row (Auto aligns by row/col/cell).
                      </div>

                      {assignExtraColumns.length === 0 ? (
                        <div style={{ ...muted, fontSize: 13 }}>No extra columns defined (go back to “Define Output” to add).</div>
                      ) : (
                        <div style={{ display: "grid", gap: 12 }}>
                          {assignExtraColumns.map((col, ci) => (
                            <div key={ci} style={{ border: `1px solid ${tokens.border}`, borderRadius: 14, padding: 12, background: tokens.surface }}>
                              <div style={{ display: "flex", gap: 10, alignItems: "center", marginBottom: 10 }}>
                                <div style={{ fontWeight: 800 }}>{col.header.trim() || `Extra column ${ci + 1}`}</div>
                                <div style={{ ...muted, fontSize: 12 }}>
                                  (Example: single-column range maps by role-row; single-row range maps by entitlement-column)
                                </div>
                              </div>

                              {col.rangesA1.map((r, ri) => (
                                <div key={ri} style={{ display: "grid", gridTemplateColumns: "1fr auto", gap: 10, marginBottom: 10 }}>
                                  <input
                                    style={input}
                                    placeholder="Range (e.g. C13:C50 or E12:AP12)"
                                    value={r}
                                    onChange={(e) =>
                                      setAssignExtraColumns((prev) =>
                                        prev.map((x, i) =>
                                          i === ci ? { ...x, rangesA1: x.rangesA1.map((rr, j) => (j === ri ? e.target.value : rr)) } : x
                                        )
                                      )
                                    }
                                  />
                                  <button
                                    style={btnStyle("ghost")}
                                    disabled={col.rangesA1.length <= 1}
                                    onClick={() =>
                                      setAssignExtraColumns((prev) =>
                                        prev.map((x, i) => (i === ci ? { ...x, rangesA1: x.rangesA1.filter((_, j) => j !== ri) } : x))
                                      )
                                    }
                                  >
                                    Remove
                                  </button>
                                </div>
                              ))}

                              <button style={btnStyle("ghost")} onClick={() => setAssignExtraColumns((prev) => prev.map((x, i) => (i === ci ? { ...x, rangesA1: [...x.rangesA1, ""] } : x)))}>
                                + Add range
                              </button>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>

                    <FiltersBlock
                      which="assignments"
                      filters={assignFilters}
                      setFilters={setAssignFilters}
                      outputFields={assignOutputFields}
                      onAddFilter={addFilter}
                      onClear={clearFilters}
                      opLabel={opLabel}
                      muted={muted}
                      inputStyle={input}
                      btnStyle={btnStyle}
                      tokens={tokens}
                    />
                  </>
                )}
              </>
            )}

            {step === 4 && (
              <>
                <h3 style={{ marginTop: 0, marginBottom: 10 }}>Generate CSV</h3>

                <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center", marginBottom: 10 }}>
  <button style={btnStyle("ghost")} onClick={onSaveTemplate}>
    Save template (JSON)
  </button>

  <button
    style={btnStyle("ghost")}
    onClick={() => compareCsvRef.current?.click()}
    disabled={mode === "roles" ? !rolesCsv : !assignCsv}
    title="Select another CSV to compare with the generated output"
  >
    Compare with CSV…
  </button>

  <input
    ref={compareCsvRef}
    type="file"
    accept=".csv,text/csv"
    style={{ display: "none" }}
    onChange={(e) => {
      const f = e.target.files?.[0];
      if (f) onCompareCsvFile(f);
      e.currentTarget.value = "";
    }}
  />

  {compareReportTxt && (
    <button
      style={btnStyle("ghost")}
      onClick={() => downloadText("compare-report.txt", compareReportTxt)}
      title="Download comparison report"
    >
      Download compare-report.txt
    </button>
  )}

  <div style={{ ...muted, fontSize: 12, marginLeft: 6 }}>
    Saves your current output definitions, ranges, and filters for importing later.
  </div>
</div>

{compareSummary && (
  <pre
    style={{
      marginTop: 10,
      maxHeight: 220,
      overflow: "auto",
      background: tokens.codeBg,
      color: tokens.codeText,
      padding: 12,
      borderRadius: 14,
      border: `1px solid ${tokens.border}`,
      fontSize: 12,
      whiteSpace: "pre-wrap",
    }}
  >
    {compareSummary}
  </pre>
)}

                {mode === "roles" ? (
                  <>
                    <button style={btnStyle("primary")} onClick={generateRecordsCsv}>
                      Generate Records CSV
                    </button>

                    {rolesWarnings.length > 0 && (
                      <div
                        style={{
                          marginTop: 12,
                          padding: 12,
                          borderRadius: 14,
                          border: `1px solid ${tokens.warnBorder}`,
                          background: tokens.warnBg,
                          color: tokens.text,
                        }}
                      >
                        <div style={{ fontWeight: 800, marginBottom: 6 }}>Warnings</div>
                        <ul style={{ margin: 0, paddingLeft: 18 }}>
                          {rolesWarnings.map((w, i) => (
                            <li key={i}>{w}</li>
                          ))}
                        </ul>
                      </div>
                    )}

                    {rolesCsv && (
                      <div style={{ marginTop: 12 }}>
                        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
                          <button style={btnStyle("ghost")} onClick={() => downloadText("records.csv", rolesCsv)}>
                            Download records.csv
                          </button>
                          {rolesDupCsv && (
                            <button style={btnStyle("ghost")} onClick={() => downloadText("records.duplicates.csv", rolesDupCsv)}>
                              Download records.duplicates.csv
                            </button>
                          )}
                        </div>
                        <pre
                          style={{
                            marginTop: 10,
                            maxHeight: 320,
                            overflow: "auto",
                            background: tokens.codeBg,
                            color: tokens.codeText,
                            padding: 12,
                            borderRadius: 14,
                            border: `1px solid ${tokens.border}`,
                            fontSize: 12,
                          }}
                        >
                          {rolesCsv}
                        </pre>
                      </div>
                    )}
                  </>
                ) : (
                  <>
                    <button style={btnStyle("primary")} onClick={generateAssignmentsCsv}>
                      Generate Assignments CSV
                    </button>

                    {assignWarnings.length > 0 && (
                      <div
                        style={{
                          marginTop: 12,
                          padding: 12,
                          borderRadius: 14,
                          border: `1px solid ${tokens.warnBorder}`,
                          background: tokens.warnBg,
                          color: tokens.text,
                        }}
                      >
                        <div style={{ fontWeight: 800, marginBottom: 6 }}>Warnings</div>
                        <ul style={{ margin: 0, paddingLeft: 18 }}>
                          {assignWarnings.map((w, i) => (
                            <li key={i}>{w}</li>
                          ))}
                        </ul>
                      </div>
                    )}

                    {assignCsv && (
                      <div style={{ marginTop: 12 }}>
                        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
                          <button style={btnStyle("ghost")} onClick={() => downloadText("assignments.csv", assignCsv)}>
                            Download assignments.csv
                          </button>
                          {assignDupCsv && (
                            <button style={btnStyle("ghost")} onClick={() => downloadText("assignments.duplicates.csv", assignDupCsv)}>
                              Download assignments.duplicates.csv
                            </button>
                          )}
                        </div>
                        <pre
                          style={{
                            marginTop: 10,
                            maxHeight: 320,
                            overflow: "auto",
                            background: tokens.codeBg,
                            color: tokens.codeText,
                            padding: 12,
                            borderRadius: 14,
                            border: `1px solid ${tokens.border}`,
                            fontSize: 12,
                          }}
                        >
                          {assignCsv}
                        </pre>
                      </div>
                    )}
                  </>
                )}
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
