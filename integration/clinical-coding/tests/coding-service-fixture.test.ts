import { describe, expect, it } from "vitest";
import type { Icd10SearchResult } from "../../../src/features/clinical-coding/coding-search";
import { validateMitCode } from "../../../src/features/clinical-coding/deterministic-validation";
import { evaluateMachineRules, SOUTH_AFRICAN_BASE_RULES } from "../../../src/features/clinical-coding/rule-engine";

const injury: Icd10SearchResult = {
  id: "00000000-0000-0000-0000-000000000001",
  code: "S82.80",
  official_description: "Fracture of other parts of lower leg, closed",
  valid_clinical_use: true,
  valid_primary: true,
  valid_asterisk: false,
  valid_dagger: false,
  valid_sequelae: false,
  age_range: null,
  gender: "U",
  source_release_id: "00000000-0000-0000-0000-000000000002",
  sa_start_date: null,
  sa_end_date: null,
  match_reason: "exact_code",
  relevance: 1,
};

describe("combined candidate validation fixture", () => {
  it("keeps MIT validity and relationship rules separate", () => {
    const mit = validateMitCode({
      code: injury.code,
      validClinicalUse: injury.valid_clinical_use,
      validPrimary: injury.valid_primary,
      validAsterisk: injury.valid_asterisk,
      validDagger: injury.valid_dagger,
      gender: injury.gender,
      saStartDate: injury.sa_start_date,
      saEndDate: injury.sa_end_date,
    }, { position: "primary", patientSex: "U", serviceDate: "2026-09-20" });

    const current = { code: injury.code, normalizedCode: "S8280", position: "primary" as const };
    const relational = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { currentCode: current, selectedCodes: [current] });

    expect(mit.some((x) => x.blocking)).toBe(false);
    expect(relational.some((x) => x.ruleCode === "INJURY_EXTERNAL_CAUSE_REQUIRED")).toBe(true);
  });
});
