import type { Icd10SearchResult } from "./coding-search";
import type { ValidationMessage } from "./deterministic-validation";

export type CodingCandidateCard = {
  codeId: string;
  code: string;
  officialDescription: string;
  matchLabel: "Exact code" | "Code family" | "Exact term" | "Known synonym" | "Text match" | "Fuzzy match";
  validityLabel: "SA-valid" | "Not valid for clinical use";
  primaryLabel: "Primary allowed" | "Not valid as primary";
  warnings: ValidationMessage[];
  sourceReleaseId: string;
};

const MATCH_LABEL: Record<Icd10SearchResult["match_reason"], CodingCandidateCard["matchLabel"]> = {
  exact_code: "Exact code",
  code_prefix: "Code family",
  exact_description: "Exact term",
  exact_alias: "Known synonym",
  full_text: "Text match",
  fuzzy_description: "Fuzzy match",
  fuzzy_alias: "Fuzzy match",
};

export function toCandidateCard(result: Icd10SearchResult, warnings: ValidationMessage[] = []): CodingCandidateCard {
  return {
    codeId: result.id,
    code: result.code,
    officialDescription: result.official_description,
    matchLabel: MATCH_LABEL[result.match_reason],
    validityLabel: result.valid_clinical_use ? "SA-valid" : "Not valid for clinical use",
    primaryLabel: result.valid_primary ? "Primary allowed" : "Not valid as primary",
    warnings,
    sourceReleaseId: result.source_release_id,
  };
}

export type CodingSearchScreenState =
  | { kind: "idle" }
  | { kind: "searching"; query: string }
  | { kind: "results"; query: string; candidates: CodingCandidateCard[] }
  | { kind: "empty"; query: string; message: string }
  | { kind: "error"; query: string; message: string; retryable: boolean };
