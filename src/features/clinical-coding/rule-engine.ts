import type { ValidationMessage, ValidationSeverity } from "./deterministic-validation";

export type CodingPosition = "primary" | "secondary";

export type SelectedCode = {
  code: string;
  normalizedCode: string;
  position: CodingPosition;
  validAsterisk?: boolean;
  validDagger?: boolean;
  validSequelae?: boolean;
};

export type RuleContext = {
  selectedCodes: SelectedCode[];
  currentCode: SelectedCode;
};

export type RuleCondition =
  | { kind: "code_prefix"; prefixes: string[] }
  | { kind: "code_range_prefix"; startsWithAny: string[] }
  | { kind: "position"; position: CodingPosition }
  | { kind: "flag"; flag: "validAsterisk" | "validDagger" | "validSequelae"; equals: boolean }
  | { kind: "requires_selected_prefix"; prefixes: string[]; position?: CodingPosition }
  | { kind: "requires_any_selected"; predicate: RuleCondition }
  | { kind: "all"; conditions: RuleCondition[] }
  | { kind: "any"; conditions: RuleCondition[] }
  | { kind: "not"; condition: RuleCondition };

export type RuleOutcome = {
  severity: ValidationSeverity;
  message: string;
  blocking?: boolean;
};

export type MachineRule = {
  ruleCode: string;
  title: string;
  authority: "NDOH" | "PHISC";
  sourceReference: string;
  condition: RuleCondition;
  outcome: RuleOutcome;
};

const codeMatches = (code: string, prefixes: string[]) => prefixes.some((p) => code.startsWith(p.toUpperCase()));

function evalCondition(condition: RuleCondition, ctx: RuleContext): boolean {
  const code = ctx.currentCode.normalizedCode.toUpperCase();

  switch (condition.kind) {
    case "code_prefix":
      return codeMatches(code, condition.prefixes);
    case "code_range_prefix":
      return codeMatches(code, condition.startsWithAny);
    case "position":
      return ctx.currentCode.position === condition.position;
    case "flag":
      return Boolean(ctx.currentCode[condition.flag]) === condition.equals;
    case "requires_selected_prefix":
      return ctx.selectedCodes.some(
        (x) => (!condition.position || x.position === condition.position) && codeMatches(x.normalizedCode.toUpperCase(), condition.prefixes),
      );
    case "requires_any_selected":
      return ctx.selectedCodes.some((candidate) =>
        evalCondition(condition.predicate, { ...ctx, currentCode: candidate }),
      );
    case "all":
      return condition.conditions.every((x) => evalCondition(x, ctx));
    case "any":
      return condition.conditions.some((x) => evalCondition(x, ctx));
    case "not":
      return !evalCondition(condition.condition, ctx);
  }
}

export function evaluateMachineRules(rules: MachineRule[], ctx: RuleContext): ValidationMessage[] {
  return rules.flatMap((rule) => {
    if (!evalCondition(rule.condition, ctx)) return [];
    return [{
      ruleCode: rule.ruleCode,
      severity: rule.outcome.severity,
      message: rule.outcome.message,
      blocking: Boolean(rule.outcome.blocking),
    } satisfies ValidationMessage];
  });
}

/**
 * Conservative baseline rules grounded in the South African national coding standards.
 * These are intentionally few. Chapter-specific PHISC rules should be added from a
 * versioned source release and clinician-reviewed before becoming machine-executable.
 */
export const SOUTH_AFRICAN_BASE_RULES: MachineRule[] = [
  {
    ruleCode: "EXTERNAL_CAUSE_NOT_PRIMARY",
    title: "External cause codes cannot be primary",
    authority: "NDOH",
    sourceReference: "SA ICD-10 Morbidity Coding Standards v6, sequencing rules / DSN20",
    condition: {
      kind: "all",
      conditions: [
        { kind: "code_range_prefix", startsWithAny: ["V", "W", "X", "Y"] },
        { kind: "position", position: "primary" },
      ],
    },
    outcome: {
      severity: "BLOCKING",
      blocking: true,
      message: "External-cause codes (V–Y) are secondary morbidity codes and cannot be confirmed in the primary position.",
    },
  },
  {
    ruleCode: "INJURY_EXTERNAL_CAUSE_REQUIRED",
    title: "Chapter XIX injury/poisoning requires an external cause code",
    authority: "NDOH",
    sourceReference: "SA ICD-10 Morbidity Coding Standards v6, DSN19",
    condition: {
      kind: "all",
      conditions: [
        { kind: "code_range_prefix", startsWithAny: ["S", "T"] },
        {
          kind: "not",
          condition: {
            kind: "requires_any_selected",
            predicate: { kind: "code_range_prefix", startsWithAny: ["V", "W", "X", "Y"] },
          },
        },
      ],
    },
    outcome: {
      severity: "WARNING",
      blocking: false,
      message: "A Chapter XIX injury/poisoning code normally requires an additional external-cause code (V–Y). Add the appropriate external-cause code or document why the rule does not apply.",
    },
  },
  {
    ruleCode: "ASTERISK_NOT_PRIMARY",
    title: "Asterisk code cannot be primary",
    authority: "NDOH",
    sourceReference: "South African ICD-10 Technical User Guide, dagger/asterisk convention",
    condition: {
      kind: "all",
      conditions: [
        { kind: "flag", flag: "validAsterisk", equals: true },
        { kind: "position", position: "primary" },
      ],
    },
    outcome: {
      severity: "BLOCKING",
      blocking: true,
      message: "An asterisk manifestation code cannot be used in the primary position.",
    },
  },
  {
    ruleCode: "ASTERISK_REQUIRES_DAGGER_CONTEXT",
    title: "Asterisk code requires an underlying dagger context",
    authority: "NDOH",
    sourceReference: "South African ICD-10 Technical User Guide, dagger/asterisk convention",
    condition: {
      kind: "all",
      conditions: [
        { kind: "flag", flag: "validAsterisk", equals: true },
        {
          kind: "not",
          condition: { kind: "requires_any_selected", predicate: { kind: "flag", flag: "validDagger", equals: true } },
        },
      ],
    },
    outcome: {
      severity: "WARNING",
      blocking: false,
      message: "This asterisk manifestation code should be sequenced with the applicable underlying dagger code. Review the documented diagnosis and add the underlying code where required.",
    },
  },
  {
    ruleCode: "CAUSATIVE_ORGANISM_NOT_PRIMARY",
    title: "B95–B98 causative organism codes cannot be primary",
    authority: "NDOH",
    sourceReference: "SA ICD-10 Morbidity Coding Standards v6, sequencing rules",
    condition: {
      kind: "all",
      conditions: [
        { kind: "code_prefix", prefixes: ["B95", "B96", "B97", "B98"] },
        { kind: "position", position: "primary" },
      ],
    },
    outcome: {
      severity: "BLOCKING",
      blocking: true,
      message: "B95–B98 causative-organism codes cannot be confirmed as the primary diagnosis.",
    },
  },
];
