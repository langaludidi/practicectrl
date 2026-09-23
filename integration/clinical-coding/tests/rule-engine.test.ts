import { describe, expect, it } from "vitest";
import { evaluateMachineRules, SOUTH_AFRICAN_BASE_RULES, type SelectedCode } from "../../../src/features/clinical-coding/rule-engine";

const code = (value: string, position: "primary" | "secondary" = "primary", extra: Partial<SelectedCode> = {}): SelectedCode => ({
  code: value,
  normalizedCode: value.replace(/[^A-Za-z0-9*]+/g, "").toUpperCase(),
  position,
  ...extra,
});

describe("South African deterministic coding rules", () => {
  it("blocks an external-cause code used as primary", () => {
    const current = code("W10.09", "primary");
    const messages = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { currentCode: current, selectedCodes: [current] });
    expect(messages.some((x) => x.ruleCode === "EXTERNAL_CAUSE_NOT_PRIMARY" && x.blocking)).toBe(true);
  });

  it("warns when an injury has no external-cause code", () => {
    const current = code("S82.80", "primary");
    const messages = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { currentCode: current, selectedCodes: [current] });
    expect(messages.some((x) => x.ruleCode === "INJURY_EXTERNAL_CAUSE_REQUIRED")).toBe(true);
  });

  it("clears the injury external-cause warning when a V-W-X-Y code is present", () => {
    const current = code("S82.80", "primary");
    const ecc = code("W10.09", "secondary");
    const messages = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { currentCode: current, selectedCodes: [current, ecc] });
    expect(messages.some((x) => x.ruleCode === "INJURY_EXTERNAL_CAUSE_REQUIRED")).toBe(false);
  });

  it("blocks an asterisk code in primary position", () => {
    const current = code("G01*", "primary", { validAsterisk: true });
    const messages = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { currentCode: current, selectedCodes: [current] });
    expect(messages.some((x) => x.ruleCode === "ASTERISK_NOT_PRIMARY" && x.blocking)).toBe(true);
  });

  it("warns when an asterisk code has no dagger context", () => {
    const current = code("G01*", "secondary", { validAsterisk: true });
    const messages = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { currentCode: current, selectedCodes: [current] });
    expect(messages.some((x) => x.ruleCode === "ASTERISK_REQUIRES_DAGGER_CONTEXT")).toBe(true);
  });

  it("accepts an asterisk context when a dagger code is selected", () => {
    const current = code("G01*", "secondary", { validAsterisk: true });
    const dagger = code("A17.0+", "primary", { validDagger: true });
    const messages = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { currentCode: current, selectedCodes: [dagger, current] });
    expect(messages.some((x) => x.ruleCode === "ASTERISK_REQUIRES_DAGGER_CONTEXT")).toBe(false);
  });
});
