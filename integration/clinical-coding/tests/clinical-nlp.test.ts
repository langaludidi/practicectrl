import { describe, expect, it } from "vitest";
import { validateClinicalConceptExtraction, validateMinimalClinicalText } from "../../../src/features/clinical-coding/clinical-nlp";

describe("AI concept extraction guardrails", () => {
  it("rejects overlong narrative input", () => {
    expect(() => validateMinimalClinicalText("x".repeat(4001))).toThrow(/4000/);
  });

  it("caps model output and preserves negation", () => {
    const result = validateClinicalConceptExtraction({
      concepts: Array.from({ length: 10 }, (_, i) => ({
        term: `concept ${i}`,
        kind: "diagnosis" as const,
        negated: i === 0,
        confidenceLabel: "possible" as const,
      })),
      documentationQuestions: Array.from({ length: 8 }, (_, i) => `Question ${i}?`),
    });
    expect(result.concepts).toHaveLength(8);
    expect(result.concepts[0].negated).toBe(true);
    expect(result.documentationQuestions).toHaveLength(6);
  });
});
