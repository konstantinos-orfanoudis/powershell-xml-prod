import type { SchemaEntity } from "../utils/normalizeSchema";

export type ValidatorSeverity = "error" | "warning" | "info";

export interface ValidatorIssue {
  id: string;
  message: string;
  code?: string;
  severity: ValidatorSeverity;
  line: number;
  column?: number;
  length?: number;
  relatedPath?: string;
}

export interface EntityExpectation {
  entity: string;
  operations: Array<"List" | "Insert" | "Update" | "Delete">;
  hasClass: boolean;
}

export interface ValidationSummary {
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

export type ScriptRuleCategory = "security" | "performance" | "quality";

export type ScriptRuleSeverity = "critical" | "high" | "medium" | "low";

export type ScriptRuleReferenceKind = "policy" | "advisory-search" | "cve";

export type ScriptRuleReferenceConfidence = "low" | "medium" | "high";

export interface ScriptRuleReference {
  id: string;
  title: string;
  authority: string;
  url: string;
  kind: ScriptRuleReferenceKind;
  confidence: ScriptRuleReferenceConfidence;
}

export interface ScriptRuleViolation {
  id: string;
  code: string;
  title: string;
  category: ScriptRuleCategory;
  severity: ScriptRuleSeverity;
  scoreImpact: number;
  evidence: string;
  fix: string;
  line?: number;
  references?: ScriptRuleReference[];
}

export interface ScriptAudit {
  totalScore: number;
  summary: string;
  violatedRules: ScriptRuleViolation[];
}

export interface ValidationReport {
  issues: ValidatorIssue[];
  summary: ValidationSummary;
  analysis: string;
  scriptAudit: ScriptAudit;
  derivedSchema: SchemaEntity[];
}

export interface ValidationReportExportRequest {
  report: ValidationReport;
  xmlFileName?: string;
  psFileName?: string;
  generatedAt?: string;
}
