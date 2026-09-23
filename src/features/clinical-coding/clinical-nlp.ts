export type ExtractedClinicalConcept = {
  term: string;
  kind: "diagnosis" | "symptom" | "complication" | "finding" | "context";
  negated: boolean;
  confidenceLabel: "strong" | "possible";
};

export type ClinicalConceptExtraction = {
  concepts: ExtractedClinicalConcept[];
  documentationQuestions: string[];
};

export type ClinicalConceptExtractor = {
  provider: string;
  modelId: string;
  extract(input: { minimalClinicalText: string }): Promise<ClinicalConceptExtraction>;
};

const MAX_TEXT = 4000;
const MAX_CONCEPTS = 8;
const MAX_QUESTIONS = 6;

export function validateMinimalClinicalText(text: string): string {
  const value = text.trim();
  if (value.length < 3) throw new Error("Clinical text is too short for concept extraction.");
  if (value.length > MAX_TEXT) throw new Error(`Clinical text exceeds the ${MAX_TEXT}-character AI-assist limit.`);
  return value;
}

/**
 * Fail-closed validation of model output. AI returns clinical search concepts only — never
 * an authoritative ICD-10 decision. Negated concepts are retained for audit/explanation
 * but are not sent to deterministic code search.
 */
export function validateClinicalConceptExtraction(value: ClinicalConceptExtraction): ClinicalConceptExtraction {
  if (!Array.isArray(value.concepts) || !Array.isArray(value.documentationQuestions)) {
    throw new Error("Invalid clinical concept extraction payload.");
  }

  const concepts = value.concepts.slice(0, MAX_CONCEPTS).map((x) => {
    const term = String(x.term ?? "").trim();
    if (term.length < 2 || term.length > 160) throw new Error("Invalid extracted clinical term.");
    if (!(["diagnosis", "symptom", "complication", "finding", "context"] as const).includes(x.kind)) {
      throw new Error("Invalid extracted concept kind.");
    }
    if (!(["strong", "possible"] as const).includes(x.confidenceLabel)) {
      throw new Error("Invalid extracted confidence label.");
    }
    return { term, kind: x.kind, negated: Boolean(x.negated), confidenceLabel: x.confidenceLabel };
  });

  const documentationQuestions = value.documentationQuestions.slice(0, MAX_QUESTIONS).map((q) => {
    const question = String(q ?? "").trim();
    if (!question || question.length > 240) throw new Error("Invalid documentation question.");
    return question;
  });

  return { concepts, documentationQuestions };
}
