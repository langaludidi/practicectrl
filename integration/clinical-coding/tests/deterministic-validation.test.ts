import { describe, expect, it } from "vitest";
import { validateMitCode } from "../../../src/features/clinical-coding/deterministic-validation";

const base = {
  code: "X00.0",
  validClinicalUse: true,
  validPrimary: true,
  validAsterisk: false,
  validDagger: false,
  gender: "U" as const,
  saStartDate: null,
  saEndDate: null,
};

const ctx = { position: "primary" as const, patientSex: "U" as const, serviceDate: "2026-09-20" };

describe("deterministic MIT validation", () => {
  it("blocks codes not valid for clinical use", () => {
    expect(validateMitCode({ ...base, validClinicalUse: false }, ctx).some((x) => x.ruleCode === "CODE_NOT_CLINICALLY_VALID" && x.blocking)).toBe(true);
  });

  it("blocks a primary-position violation", () => {
    expect(validateMitCode({ ...base, validPrimary: false }, ctx).some((x) => x.ruleCode === "PRIMARY_NOT_ALLOWED" && x.blocking)).toBe(true);
  });

  it("warns rather than silently correcting a gender conflict", () => {
    const result = validateMitCode({ ...base, gender: "M" }, { ...ctx, patientSex: "F" });
    expect(result.find((x) => x.ruleCode === "GENDER_CONFLICT")?.severity).toBe("WARNING");
  });

  it("blocks a code outside its South African effective window", () => {
    const result = validateMitCode({ ...base, saEndDate: "2025-12-31" }, ctx);
    expect(result.some((x) => x.ruleCode === "AFTER_SA_END_DATE" && x.blocking)).toBe(true);
  });
});
