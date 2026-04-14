import type { SchemaEntity } from "../utils/normalizeSchema";
import {
  prepareXmlForValidation,
  validateConnector,
  type Issue,
} from "../utils/validation";
import { parseFnName, parsePsFileToFns, type Fn, type PsParam, type UiType } from "@/lib/ps-parse";
import { buildXmlFromUploadPw, classifyParamsForUpload } from "@/lib/uploadPwxml";

type Operation = "List" | "Insert" | "Update" | "Delete";

export type ValidatorIssue = Issue;

export interface EntityExpectation {
  entity: string;
  operations: Operation[];
  hasClass: boolean;
}

export interface SignatureSummary {
  totalFunctions: number;
  globalFunctions: string[];
  helperFunctions: string[];
  xmlClasses: string[];
  customCommands: string[];
  predefinedCommands: string[];
  inferredConnectionParameters: string[];
  actualConnectionParameters: string[];
  expectedEntities: EntityExpectation[];
}

export interface ValidationReport {
  issues: ValidatorIssue[];
  summary: SignatureSummary;
  referenceXml?: string;
  derivedSchema: SchemaEntity[];
}

interface XmlClassProperty {
  name: string;
  uiType: UiType | "Unknown";
  line: number;
}

interface XmlCommandRef {
  command: string;
  line: number;
  tag: "ListingCommand" | "Item" | "Map" | "ModBy" | "Bind";
  className?: string;
  parameter?: string;
  propertyName?: string;
  propertyType?: UiType | "Unknown";
  source?: string;
  path?: string;
}

interface XmlClassFacts {
  name: string;
  line: number;
  hasReadConfiguration: boolean;
  readConfigurationLine: number;
  methodCommandMap: Map<string, Set<string>>;
  propertyMap: Map<string, XmlClassProperty>;
  methodNames: Set<string>;
}

interface XmlFacts {
  rootName: string;
  classes: XmlClassFacts[];
  connectionParameters: Array<{ name: string; line: number }>;
  customCommands: Array<{ name: string; line: number }>;
  predefinedCommands: Array<{ name: string; line: number }>;
  commandRefs: XmlCommandRef[];
}

function isModulePathLikeName(name?: string) {
  const normalized = String(name || "")
    .trim()
    .toLowerCase()
    .replace(/^_+/, "");

  if (!normalized) return false;

  return (
    normalized === "pathtopsmodule" ||
    normalized === "psmodulepath" ||
    normalized === "modulepath" ||
    normalized === "powershellmodulepath" ||
    normalized === "pathtopowershellmodule"
  );
}

const OP_LABELS: Record<Operation, string> = {
  List: "List",
  Insert: "Insert",
  Update: "Update",
  Delete: "Delete",
};

function buildLineIndex(text: string) {
  const starts: number[] = [0];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\n") starts.push(i + 1);
  }
  return starts;
}

function posToLineCol(starts: number[], pos: number) {
  let lo = 0;
  let hi = starts.length - 1;

  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (starts[mid] <= pos) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }

  const line = hi + 1;
  const column = pos - starts[hi] + 1;
  return { line, column };
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function locateTagAttr(
  xmlText: string,
  starts: number[],
  tag: string,
  attrName?: string,
  attrValue?: string
) {
  let re: RegExp;

  if (attrName && attrValue != null) {
    re = new RegExp(
      `<\\s*${tag}\\b[^>]*\\b${escapeRegExp(attrName)}\\s*=\\s*["']${escapeRegExp(attrValue)}["']`,
      "i"
    );
  } else {
    re = new RegExp(`<\\s*${tag}\\b`, "i");
  }

  const match = re.exec(xmlText);
  if (!match) return null;

  const { line, column } = posToLineCol(starts, match.index);
  return { line, column, length: match[0].length };
}

function makeIssue(
  xmlText: string,
  starts: number[],
  message: string,
  code: string,
  severity: Issue["severity"],
  opts: {
    line?: number;
    column?: number;
    length?: number;
    relatedPath?: string;
    tag?: string;
    attrName?: string;
    attrValue?: string;
  } = {}
): ValidatorIssue {
  let line = opts.line ?? 1;
  let column = opts.column;
  let length = opts.length;

  if (opts.tag) {
    const loc = locateTagAttr(xmlText, starts, opts.tag, opts.attrName, opts.attrValue);
    if (loc) {
      line = loc.line;
      column = loc.column;
      length = loc.length;
    }
  }

  return {
    id: `${code}-${line}-${Math.random().toString(36).slice(2, 8)}`,
    message,
    code,
    severity,
    line,
    column,
    length,
    relatedPath: opts.relatedPath,
  };
}

function normalizeXmlType(value?: string): UiType | "Unknown" {
  const lowered = String(value || "").trim().toLowerCase();
  if (lowered === "string") return "String";
  if (lowered === "bool") return "Bool";
  if (lowered === "int") return "Int";
  if (lowered === "datetime") return "DateTime";
  return "Unknown";
}

function inferUiTypeFromPsExpression(expr: string): UiType | "Unknown" {
  const value = expr.trim();
  if (/^\$true$/i.test(value) || /^\$false$/i.test(value)) return "Bool";
  if (/^[+-]?\d+$/.test(value)) return "Int";
  if (/^["'][\s\S]*["']$/.test(value)) return "String";
  if (/\[datetime\]/i.test(value)) return "DateTime";
  if (/Get-Date\b/i.test(value)) return "DateTime";
  if (/DateTime::(UtcNow|Now|Parse|ParseExact)\b/i.test(value)) return "DateTime";
  return "Unknown";
}

function extractBalanced(
  src: string,
  openIdx: number,
  openChar: string,
  closeChar: string
): { text: string; end: number } | null {
  let depth = 0;
  let start = -1;

  for (let i = openIdx; i < src.length; i++) {
    const ch = src[i];
    if (ch === openChar) {
      if (depth === 0) start = i + 1;
      depth += 1;
    } else if (ch === closeChar) {
      depth -= 1;
      if (depth === 0) {
        return { text: src.slice(start, i), end: i + 1 };
      }
    }
  }

  return null;
}

function parseReturnShapes(functions: Fn[]) {
  const shapes = new Map<string, Record<string, UiType | "Unknown">>();

  for (const fn of functions) {
    const fnShapes: Record<string, UiType | "Unknown"> = {};
    const re = /\[\s*pscustomobject\s*\]\s*@\s*\{/gi;
    let match: RegExpExecArray | null;

    while ((match = re.exec(fn.script || ""))) {
      const openIdx = (fn.script || "").indexOf("{", match.index);
      if (openIdx < 0) continue;

      const block = extractBalanced(fn.script || "", openIdx, "{", "}");
      if (!block) continue;

      const assignRe = /([A-Za-z0-9_]+)\s*=\s*([^\r\n;]+)/g;
      let assign: RegExpExecArray | null;

      while ((assign = assignRe.exec(block.text))) {
        const key = assign[1];
        if (!fnShapes[key]) {
          fnShapes[key] = inferUiTypeFromPsExpression(assign[2]);
        }
      }
    }

    if (Object.keys(fnShapes).length > 0) {
      shapes.set(fn.name.toLowerCase(), fnShapes);
    }
  }

  return shapes;
}

function isGlobalFunction(fn: Fn) {
  const escaped = escapeRegExp(String(fn.name || "").trim());
  return new RegExp(`\\bfunction\\s+global:\\s*${escaped}\\b`, "i").test(fn.script || "");
}

function readAttr(el: Element, ...names: string[]) {
  for (const name of names) {
    const value = el.getAttribute(name);
    if (value != null) return value;
  }
  return "";
}

function deriveSchemaFromXml(doc: Document): SchemaEntity[] {
  return Array.from(doc.getElementsByTagName("Class")).map((classEl) => ({
    name: readAttr(classEl, "Name", "name"),
    attributes: Array.from(classEl.getElementsByTagName("Property"))
      .map((propertyEl) => ({
        name: readAttr(propertyEl, "Name", "name"),
        type: readAttr(propertyEl, "DataType", "datatype"),
      }))
      .filter((property) => property.name),
  })).filter((entity) => entity.name);
}

function getCommandParamMap(
  functions: Fn[],
  xmlText: string
): Map<string, { name: string; inputs: PsParam[]; source: "powershell" | "custom" }> {
  const map = new Map<string, { name: string; inputs: PsParam[]; source: "powershell" | "custom" }>();

  for (const fn of functions) {
    map.set(fn.name.toLowerCase(), {
      name: fn.name,
      inputs: fn.inputs || [],
      source: "powershell",
    });
  }

  const customCommandRe =
    /<CustomCommand\b[^>]*Name="([^"]+)"[^>]*>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/CustomCommand>/gi;
  let match: RegExpExecArray | null;

  while ((match = customCommandRe.exec(xmlText))) {
    const name = match[1];
    const body = match[2];
    const parsed = parsePsFileToFns(`function global:${name} {\n${body}\n}`)[0];

    map.set(name.toLowerCase(), {
      name,
      inputs: parsed?.inputs || [],
      source: "custom",
    });
  }

  return map;
}

function parseXmlFacts(xmlText: string): XmlFacts {
  const starts = buildLineIndex(xmlText);
  const preparedXml = prepareXmlForValidation(xmlText);
  const doc = new DOMParser().parseFromString(preparedXml.xmlForParsing, "application/xml");

  const classes = Array.from(doc.getElementsByTagName("Class")).map((classEl) => {
    const name = readAttr(classEl, "Name", "name");
    const propertyMap = new Map<string, XmlClassProperty>();
    const methodCommandMap = new Map<string, Set<string>>();

    for (const propertyEl of Array.from(classEl.getElementsByTagName("Property"))) {
      const propertyName = readAttr(propertyEl, "Name", "name");
      if (!propertyName) continue;
      const propertyLine =
        locateTagAttr(xmlText, starts, "Property", "Name", propertyName)?.line ?? 1;

      propertyMap.set(propertyName.toLowerCase(), {
        name: propertyName,
        uiType: normalizeXmlType(readAttr(propertyEl, "DataType", "datatype")),
        line: propertyLine,
      });
    }

    for (const methodEl of Array.from(classEl.getElementsByTagName("Method"))) {
      const methodName = readAttr(methodEl, "Name", "name");
      if (!methodName) continue;

      const commands = new Set<string>();
      for (const itemEl of Array.from(methodEl.getElementsByTagName("Item"))) {
        const commandName = readAttr(itemEl, "Command", "command");
        if (commandName) commands.add(commandName.toLowerCase());
      }

      methodCommandMap.set(methodName.toLowerCase(), commands);
    }

    const readLine =
      locateTagAttr(xmlText, starts, "ReadConfiguration")?.line ??
      locateTagAttr(xmlText, starts, "Class", "Name", name)?.line ??
      1;

    return {
      name,
      line: locateTagAttr(xmlText, starts, "Class", "Name", name)?.line ?? 1,
      hasReadConfiguration: classEl.getElementsByTagName("ReadConfiguration").length > 0,
      readConfigurationLine: readLine,
      methodCommandMap,
      propertyMap,
      methodNames: new Set(
        Array.from(classEl.getElementsByTagName("Method"))
          .map((methodEl) => readAttr(methodEl, "Name", "name"))
          .filter(Boolean)
      ),
    };
  });

  const commandRefs: XmlCommandRef[] = [];

  const pushCommandRef = (
    tag: XmlCommandRef["tag"],
    command: string,
    attrName: string,
    extra: Partial<XmlCommandRef> = {}
  ) => {
    if (!command) return;
    commandRefs.push({
      command,
      line: locateTagAttr(xmlText, starts, tag, attrName, command)?.line ?? 1,
      tag,
      ...extra,
    });
  };

  for (const listingEl of Array.from(doc.getElementsByTagName("ListingCommand"))) {
    pushCommandRef(
      "ListingCommand",
      readAttr(listingEl, "Command", "command"),
      "Command"
    );
  }

  for (const itemEl of Array.from(doc.getElementsByTagName("Item"))) {
    pushCommandRef("Item", readAttr(itemEl, "Command", "command"), "Command");
  }

  for (const mapEl of Array.from(doc.getElementsByTagName("Map"))) {
    const classEl = mapEl.parentElement?.closest?.("Class");
    const propertyEl = mapEl.parentElement?.closest?.("Property") ?? mapEl.parentElement;
    const propertyName = propertyEl ? readAttr(propertyEl, "Name", "name") : "";
    const propertyType = propertyEl
      ? normalizeXmlType(readAttr(propertyEl, "DataType", "datatype"))
      : "Unknown";

    pushCommandRef(
      "Map",
      readAttr(mapEl, "ToCommand", "tocommand"),
      "ToCommand",
      {
        className: classEl ? readAttr(classEl, "Name", "name") : "",
        parameter: readAttr(mapEl, "Parameter", "parameter"),
        propertyName,
        propertyType,
      }
    );
  }

  for (const modByEl of Array.from(doc.getElementsByTagName("ModBy"))) {
    const classEl = modByEl.parentElement?.closest?.("Class");
    const propertyEl = modByEl.parentElement?.closest?.("Property") ?? modByEl.parentElement;
    const propertyName = propertyEl ? readAttr(propertyEl, "Name", "name") : "";
    const propertyType = propertyEl
      ? normalizeXmlType(readAttr(propertyEl, "DataType", "datatype"))
      : "Unknown";

    pushCommandRef(
      "ModBy",
      readAttr(modByEl, "Command", "command"),
      "Command",
      {
        className: classEl ? readAttr(classEl, "Name", "name") : "",
        propertyName,
        propertyType,
      }
    );
  }

  for (const bindEl of [
    ...Array.from(doc.getElementsByTagName("Bind")),
    ...Array.from(doc.getElementsByTagName("ReturnBind")),
    ...Array.from(doc.getElementsByTagName("ReturnBinding")),
  ]) {
    const classEl = bindEl.parentElement?.closest?.("Class");
    const propertyEl = bindEl.parentElement?.closest?.("Property") ?? bindEl.parentElement;
    const propertyName = propertyEl ? readAttr(propertyEl, "Name", "name") : "";
    const propertyType = propertyEl
      ? normalizeXmlType(readAttr(propertyEl, "DataType", "datatype"))
      : "Unknown";

    pushCommandRef(
      "Bind",
      readAttr(bindEl, "CommandResultOf", "commandResultOf"),
      "CommandResultOf",
      {
        className: classEl ? readAttr(classEl, "Name", "name") : "",
        propertyName,
        propertyType,
        path: readAttr(bindEl, "Path", "path"),
      }
    );
  }

  return {
    rootName: doc.documentElement?.tagName || "",
    classes,
    connectionParameters: Array.from(doc.getElementsByTagName("ConnectionParameter"))
      .map((paramEl) => {
        const name = readAttr(paramEl, "Name", "name");
        return {
          name,
          line: locateTagAttr(xmlText, starts, "ConnectionParameter", "Name", name)?.line ?? 1,
        };
      })
      .filter((entry) => entry.name),
    customCommands: Array.from(doc.getElementsByTagName("CustomCommand"))
      .map((customEl) => {
        const name = readAttr(customEl, "Name", "name");
        return {
          name,
          line: locateTagAttr(xmlText, starts, "CustomCommand", "Name", name)?.line ?? 1,
        };
      })
      .filter((entry) => entry.name),
    predefinedCommands: Array.from(doc.getElementsByTagName("PredefinedCommands"))
      .flatMap((predefinedEl) =>
        Array.from(predefinedEl.getElementsByTagName("Command")).map((commandEl) => {
          const name = readAttr(commandEl, "Name", "name");
          return {
            name,
            line: locateTagAttr(xmlText, starts, "Command", "Name", name)?.line ?? 1,
          };
        })
      )
      .filter((entry) => entry.name),
    commandRefs,
  };
}

function deriveExpectedEntities(functions: Fn[]) {
  const byEntity = new Map<string, Set<Operation>>();

  for (const fn of functions) {
    const parsed = parseFnName(fn.name);
    if (!parsed.entity) continue;

    let op: Operation | null = null;
    if (parsed.verb === "Get") op = "List";
    if (parsed.verb === "Create") op = "Insert";
    if (parsed.verb === "Update") op = "Update";
    if (parsed.verb === "Delete") op = "Delete";
    if (!op) continue;

    const existing = byEntity.get(parsed.entity) ?? new Set<Operation>();
    existing.add(op);
    byEntity.set(parsed.entity, existing);
  }

  return byEntity;
}

function deriveExpectedConnectionParameters(
  globalFunctions: Fn[],
  propertyNames: Set<string>,
  includeModulePathSupport = false
) {
  const params = new Map<string, string>();

  for (const fn of globalFunctions) {
    for (const input of fn.inputs || []) {
      const normalized = String(input.name || "").trim();
      if (!normalized) continue;
      if (propertyNames.has(normalized.toLowerCase())) continue;
      if (!params.has(normalized.toLowerCase())) {
        params.set(normalized.toLowerCase(), normalized);
      }
    }
  }

  if (includeModulePathSupport && globalFunctions.length > 0 && !params.has("pathtopsmodule")) {
    params.set("pathtopsmodule", "PathToPSModule");
  }

  return Array.from(params.values());
}

function shouldExpectModulePathSupport(args: {
  globalFunctions: Fn[];
  xmlDom: Document;
  facts: XmlFacts;
}) {
  if (args.facts.connectionParameters.some((entry) => isModulePathLikeName(entry.name))) {
    return true;
  }

  for (const fn of args.globalFunctions) {
    if ((fn.inputs || []).some((input) => isModulePathLikeName(input.name))) {
      return true;
    }
  }

  for (const setParamEl of Array.from(args.xmlDom.getElementsByTagName("SetParameter"))) {
    const source = readAttr(setParamEl, "Source", "source");
    if (source !== "ConnectionParameter") continue;

    if (
      isModulePathLikeName(readAttr(setParamEl, "Value", "value")) ||
      isModulePathLikeName(readAttr(setParamEl, "Param", "param"))
    ) {
      return true;
    }
  }

  return false;
}

function getPropertyNameSet(facts: XmlFacts, schemaEntities: SchemaEntity[]) {
  const names = new Set<string>();

  for (const entity of schemaEntities) {
    for (const attr of entity.attributes || []) {
      names.add(attr.name.toLowerCase());
    }
  }

  for (const classFacts of facts.classes) {
    for (const propKey of classFacts.propertyMap.keys()) {
      names.add(propKey);
    }
  }

  return names;
}

function cloneFunctions(functions: Fn[]): Fn[] {
  return functions.map((fn) => ({
    ...fn,
    inputs: (fn.inputs || []).map((input) => ({ ...input })),
  }));
}

function sortIssues(issues: ValidatorIssue[]) {
  const severityRank = (severity: ValidatorIssue["severity"]) => {
    if (severity === "error") return 0;
    if (severity === "warning") return 1;
    return 2;
  };

  return issues.toSorted((left, right) => {
    if (left.line !== right.line) return left.line - right.line;
    if (severityRank(left.severity) !== severityRank(right.severity)) {
      return severityRank(left.severity) - severityRank(right.severity);
    }
    return (left.code || "").localeCompare(right.code || "");
  });
}

function dedupeIssues(issues: ValidatorIssue[]) {
  const seen = new Set<string>();
  return issues.filter((issue) => {
    const key = [issue.line, issue.column, issue.code, issue.message].join("|");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function validateXmlWorkspace(args: {
  xmlText: string;
  psText: string;
  schemaEntities?: SchemaEntity[];
}): ValidationReport {
  const xmlText = args.xmlText || "";
  const psText = args.psText || "";
  const starts = buildLineIndex(xmlText);
  const preparedXml = prepareXmlForValidation(xmlText || "<Connector/>");
  const parsedFunctions = parsePsFileToFns(psText);
  const globalFunctions = parsedFunctions.filter(isGlobalFunction);

  const xmlDom = new DOMParser().parseFromString(
    preparedXml.xmlForParsing || "<Connector/>",
    "application/xml"
  );
  const parseError = xmlDom.getElementsByTagName("parsererror")[0];
  const derivedSchema = parseError ? [] : deriveSchemaFromXml(xmlDom);
  const effectiveSchema = (args.schemaEntities && args.schemaEntities.length > 0)
    ? args.schemaEntities
    : derivedSchema;

  const baseIssues = xmlText.trim()
    ? validateConnector(xmlText, psText, effectiveSchema)
    : [
        makeIssue(
          xmlText,
          starts,
          "Paste or upload connector XML before running validation.",
          "validator.xml.empty",
          "warning"
        ),
      ];

  if (!psText.trim()) {
    baseIssues.push(
      makeIssue(
        xmlText,
        starts,
        "Paste or upload the PowerShell file so signature-based rules can run.",
        "validator.ps.empty",
        "warning"
      )
    );
  }

  if (parseError) {
    return {
      issues: sortIssues(dedupeIssues(baseIssues)),
      summary: {
        totalFunctions: parsedFunctions.length,
        globalFunctions: globalFunctions.map((fn) => fn.name),
        helperFunctions: parsedFunctions.filter((fn) => !isGlobalFunction(fn)).map((fn) => fn.name),
        xmlClasses: [],
        customCommands: [],
        predefinedCommands: [],
        inferredConnectionParameters: [],
        actualConnectionParameters: [],
        expectedEntities: [],
      },
      derivedSchema,
    };
  }

  const facts = parseXmlFacts(xmlText);
  const includeModulePathSupport = shouldExpectModulePathSupport({
    globalFunctions,
    xmlDom,
    facts,
  });
  const propertyNameSet = getPropertyNameSet(facts, effectiveSchema);
  const expectedEntities = deriveExpectedEntities(parsedFunctions);
  const inferredConnectionParameters = deriveExpectedConnectionParameters(
    globalFunctions,
    propertyNameSet,
    includeModulePathSupport
  );
  const commandCatalog = getCommandParamMap(parsedFunctions, xmlText);
  const returnShapes = parseReturnShapes(parsedFunctions);

  const issues: ValidatorIssue[] = [...baseIssues];
  const classMap = new Map(facts.classes.map((classFacts) => [classFacts.name.toLowerCase(), classFacts]));
  const actualConnectionParameters = new Set(
    facts.connectionParameters.map((entry) => entry.name.toLowerCase())
  );
  const declaredCommands = new Set([
    ...facts.customCommands.map((entry) => entry.name.toLowerCase()),
    ...facts.predefinedCommands.map((entry) => entry.name.toLowerCase()),
  ]);

  if (facts.rootName && facts.rootName !== "PowershellConnectorDefinition") {
    issues.push(
      makeIssue(
        xmlText,
        starts,
        `Expected root element <PowershellConnectorDefinition>, found <${facts.rootName}>.`,
        "xml.root.connector",
        "warning",
        { tag: facts.rootName }
      )
    );
  }

  if (globalFunctions.length === 0 && psText.trim()) {
    issues.push(
      makeIssue(
        xmlText,
        starts,
        "No global PowerShell functions were detected. The XML builder page relies on global function signatures for predefined commands and connection parameters.",
        "ps.global.none",
        "warning"
      )
    );
  }

  for (const predefined of facts.predefinedCommands) {
    if (!globalFunctions.some((fn) => fn.name.toLowerCase() === predefined.name.toLowerCase())) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Predefined command "${predefined.name}" is not backed by a global PowerShell function.`,
          "xml.predefined.missing-global",
          "error",
          { line: predefined.line, relatedPath: `<Command Name="${predefined.name}">` }
        )
      );
    }
  }

  for (const [entity, operations] of expectedEntities.entries()) {
    const xmlClass = classMap.get(entity.toLowerCase());
    if (!xmlClass) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `PowerShell signatures imply an entity "${entity}" (${Array.from(operations).map((op) => OP_LABELS[op]).join(", ")}) but the XML has no <Class Name="${entity}">.`,
          "signature.class.missing",
          "warning"
        )
      );
      continue;
    }

    if (operations.has("List") && !xmlClass.hasReadConfiguration) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Class "${entity}" has a list-style PowerShell function but no <ReadConfiguration> block.`,
          "signature.read-config.missing",
          "error",
          { line: xmlClass.line, relatedPath: `<Class Name="${entity}">` }
        )
      );
    }

    if (operations.has("Insert") && !xmlClass.methodNames.has("Insert")) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Class "${entity}" has a create-style PowerShell function but no <Method Name="Insert"> block.`,
          "signature.method.insert.missing",
          "warning",
          { line: xmlClass.line, relatedPath: `<Class Name="${entity}">` }
        )
      );
    }

    if (operations.has("Update") && !xmlClass.methodNames.has("Update")) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Class "${entity}" has an update-style PowerShell function but no <Method Name="Update"> block.`,
          "signature.method.update.missing",
          "warning",
          { line: xmlClass.line, relatedPath: `<Class Name="${entity}">` }
        )
      );
    }

    if (operations.has("Delete") && !xmlClass.methodNames.has("Delete")) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Class "${entity}" has a delete-style PowerShell function but no <Method Name="Delete"> block.`,
          "signature.method.delete.missing",
          "warning",
          { line: xmlClass.line, relatedPath: `<Class Name="${entity}">` }
        )
      );
    }
  }

  for (const classFacts of facts.classes) {
    if (!expectedEntities.has(classFacts.name)) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Class "${classFacts.name}" has no matching CRUD/list PowerShell signature in the uploaded script.`,
          "signature.class.unmatched",
          "info",
          { line: classFacts.line, relatedPath: `<Class Name="${classFacts.name}">` }
        )
      );
    }
  }

  for (const expectedParam of inferredConnectionParameters) {
    if (!actualConnectionParameters.has(expectedParam.toLowerCase())) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Connection parameter "${expectedParam}" is implied by the global PowerShell signatures but is missing from <ConnectionParameters>.`,
          "signature.connection-parameter.missing",
          "warning"
        )
      );
    }
  }

  for (const actualParam of facts.connectionParameters) {
    if (
      !inferredConnectionParameters.some(
        (expected) => expected.toLowerCase() === actualParam.name.toLowerCase()
      )
    ) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Connection parameter "${actualParam.name}" is not inferred from the global PowerShell signatures.`,
          "signature.connection-parameter.extra",
          "info",
          { line: actualParam.line, relatedPath: `<ConnectionParameter Name="${actualParam.name}">` }
        )
      );
    }
  }

  for (const ref of facts.commandRefs) {
    const commandKey = ref.command.toLowerCase();
    const commandInfo = commandCatalog.get(commandKey);

    if (!declaredCommands.has(commandKey)) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Command "${ref.command}" is used in <${ref.tag}> but is not declared under <PredefinedCommands> or <CustomCommands>.`,
          "xml.command.undeclared",
          "error",
          { line: ref.line, relatedPath: `<${ref.tag}>` }
        )
      );
    }

    if (!commandInfo) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Command "${ref.command}" is referenced in <${ref.tag}> but is not present in the PowerShell file or XML custom commands.`,
          "xml.command.missing",
          "error",
          { line: ref.line, relatedPath: `<${ref.tag}>` }
        )
      );
      continue;
    }

    if (ref.parameter) {
      const parameter = commandInfo.inputs.find(
        (input) => input.name.toLowerCase() === ref.parameter?.toLowerCase()
      );

      if (!parameter) {
        issues.push(
          makeIssue(
            xmlText,
            starts,
            `Parameter "${ref.parameter}" is not exposed by command "${ref.command}".`,
            `${ref.tag.toLowerCase()}.parameter.missing`,
            "error",
            { line: ref.line, relatedPath: `<${ref.tag}>` }
          )
        );
      } else if (ref.propertyName && ref.propertyType && ref.propertyType !== "Unknown") {
        const paramType = parameter.type || "String";
        if (ref.propertyType !== paramType) {
          issues.push(
            makeIssue(
              xmlText,
              starts,
              `Property "${ref.propertyName}" is ${ref.propertyType} but "${ref.command}.${parameter.name}" is ${paramType}.`,
              `${ref.tag.toLowerCase()}.type.mismatch`,
              "error",
              { line: ref.line, relatedPath: `<${ref.tag}>` }
            )
          );
        }
      }

      if (
        ref.tag === "Map" &&
        ref.propertyName &&
        ref.parameter.toLowerCase() !== ref.propertyName.toLowerCase()
      ) {
        issues.push(
          makeIssue(
            xmlText,
            starts,
            `Map uses Parameter="${ref.parameter}" for property "${ref.propertyName}". The PowerShell XML builder expects those names to line up.`,
            "map.parameter.name-mismatch",
            "warning",
            { line: ref.line, relatedPath: `<Map ToCommand="${ref.command}">` }
          )
        );
      }
    }

    if (ref.tag === "Bind" && ref.path) {
      const shape = returnShapes.get(commandKey);
      if (shape) {
        const returnType = shape[ref.path];
        if (!returnType) {
          issues.push(
            makeIssue(
              xmlText,
              starts,
              `Bind Path="${ref.path}" was not found in the PSCustomObject returned by "${ref.command}".`,
              "bind.path.not-returned",
              "error",
              { line: ref.line, relatedPath: `<Bind CommandResultOf="${ref.command}">` }
            )
          );
        } else if (
          ref.propertyType &&
          ref.propertyType !== "Unknown" &&
          returnType !== "Unknown" &&
          ref.propertyType !== returnType
        ) {
          issues.push(
            makeIssue(
              xmlText,
              starts,
              `Property "${ref.propertyName}" is ${ref.propertyType} but "${ref.command}.${ref.path}" returns ${returnType}.`,
              "bind.type.mismatch",
              "error",
              { line: ref.line, relatedPath: `<Bind CommandResultOf="${ref.command}">` }
            )
          );
        }
      }
    }

    if (ref.tag === "ModBy" && ref.className) {
      const classFacts = classMap.get(ref.className.toLowerCase());
      const insertCommands = classFacts?.methodCommandMap.get("insert") ?? new Set<string>();
      const updateCommands = classFacts?.methodCommandMap.get("update") ?? new Set<string>();
      const isMethodCommand =
        insertCommands.has(commandKey) || updateCommands.has(commandKey);

      if (!isMethodCommand) {
        issues.push(
          makeIssue(
            xmlText,
            starts,
            `ModifiedBy command "${ref.command}" is not used by the Insert or Update method configuration of class "${ref.className}".`,
            "modby.method.command.missing",
            "warning",
            { line: ref.line, relatedPath: `<ModBy Command="${ref.command}">` }
          )
        );
      }
    }
  }

  for (const setParamEl of Array.from(xmlDom.getElementsByTagName("SetParameter"))) {
    const paramName = readAttr(setParamEl, "Param", "param");
    const source = readAttr(setParamEl, "Source", "source");
    const parent = setParamEl.parentElement;
    const commandName = parent ? readAttr(parent, "Command", "command") : "";
    const line =
      locateTagAttr(xmlText, starts, "SetParameter", "Param", paramName)?.line ??
      locateTagAttr(xmlText, starts, "SetParameter")?.line ??
      1;

    if (!paramName) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          "<SetParameter> must include Param=\"...\".",
          "set-parameter.param.missing",
          "error",
          { line }
        )
      );
      continue;
    }

    if (!commandName) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `<SetParameter Param="${paramName}"> is not nested under an XML command element with Command="...".`,
          "set-parameter.command.missing",
          "error",
          { line }
        )
      );
      continue;
    }

    if (source === "ConnectionParameter" && !actualConnectionParameters.has(paramName.toLowerCase())) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `SetParameter uses Source="ConnectionParameter" for "${paramName}", but that connection parameter does not exist in the XML.`,
          "set-parameter.connection.missing",
          "error",
          { line }
        )
      );
    }

    const commandInfo = commandCatalog.get(commandName.toLowerCase());
    if (!commandInfo) continue;

    const param = commandInfo.inputs.find(
      (input) => input.name.toLowerCase() === paramName.toLowerCase()
    );

    if (!param) {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Command "${commandName}" does not expose a parameter named "${paramName}" for this <SetParameter>.`,
          "set-parameter.signature.missing",
          "error",
          { line }
        )
      );
      continue;
    }

    if (source === "ConnectionParameter" && param.type !== "String") {
      issues.push(
        makeIssue(
          xmlText,
          starts,
          `Connection parameters flow into strings in the XML builder, but "${commandName}.${param.name}" is typed as ${param.type}.`,
          "set-parameter.signature.type",
          "warning",
          { line }
        )
      );
    }
  }

  let referenceXml: string | undefined;

  if (args.schemaEntities && args.schemaEntities.length > 0 && parsedFunctions.length > 0) {
    const referenceFns = classifyParamsForUpload(
      cloneFunctions(parsedFunctions),
      { entities: args.schemaEntities }
    );
    referenceXml = buildXmlFromUploadPw(referenceFns, { entities: args.schemaEntities }, {
      includeModulePathSupport,
    });

    const referenceFacts = parseXmlFacts(referenceXml);
    const referenceClasses = new Set(
      referenceFacts.classes.map((classFacts) => classFacts.name.toLowerCase())
    );
    const actualClasses = new Set(
      facts.classes.map((classFacts) => classFacts.name.toLowerCase())
    );

    for (const classFacts of referenceFacts.classes) {
      if (!actualClasses.has(classFacts.name.toLowerCase())) {
        issues.push(
          makeIssue(
            xmlText,
            starts,
            `Reference XML generated from the uploaded schema expects <Class Name="${classFacts.name}">, but it is missing in the current XML.`,
            "reference.class.missing",
            "warning"
          )
        );
      }
    }

    for (const actualClass of facts.classes) {
      if (!referenceClasses.has(actualClass.name.toLowerCase())) {
        issues.push(
          makeIssue(
            xmlText,
            starts,
            `Class "${actualClass.name}" is not present in the reference XML generated from the current schema and PowerShell signatures.`,
            "reference.class.extra",
            "info",
            { line: actualClass.line }
          )
        );
      }
    }

    const referenceConnectionParameters = new Set(
      referenceFacts.connectionParameters.map((entry) => entry.name.toLowerCase())
    );

    for (const referenceParam of referenceFacts.connectionParameters) {
      if (!actualConnectionParameters.has(referenceParam.name.toLowerCase())) {
        issues.push(
          makeIssue(
            xmlText,
            starts,
            `Reference XML expects connection parameter "${referenceParam.name}", but it is missing in the current XML.`,
            "reference.connection-parameter.missing",
            "warning"
          )
        );
      }
    }

    for (const actualParam of facts.connectionParameters) {
      if (!referenceConnectionParameters.has(actualParam.name.toLowerCase())) {
        issues.push(
          makeIssue(
            xmlText,
            starts,
            `Connection parameter "${actualParam.name}" does not appear in the reference XML generated from the current schema and signatures.`,
            "reference.connection-parameter.extra",
            "info",
            { line: actualParam.line }
          )
        );
      }
    }
  }

  return {
    issues: sortIssues(dedupeIssues(issues)),
    summary: {
      totalFunctions: parsedFunctions.length,
      globalFunctions: globalFunctions.map((fn) => fn.name),
      helperFunctions: parsedFunctions.filter((fn) => !isGlobalFunction(fn)).map((fn) => fn.name),
      xmlClasses: facts.classes.map((classFacts) => classFacts.name),
      customCommands: facts.customCommands.map((entry) => entry.name),
      predefinedCommands: facts.predefinedCommands.map((entry) => entry.name),
      inferredConnectionParameters,
      actualConnectionParameters: facts.connectionParameters.map((entry) => entry.name),
      expectedEntities: Array.from(expectedEntities.entries()).map(([entity, operations]) => ({
        entity,
        operations: Array.from(operations),
        hasClass: classMap.has(entity.toLowerCase()),
      })),
    },
    referenceXml,
    derivedSchema,
  };
}
