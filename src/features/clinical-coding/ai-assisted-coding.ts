import type { SupabaseClient } from "@supabase/supabase-js";
import { searchClinicalCodingCandidates, type CodingSearchContext } from "./coding-service";
import {
  validateClinicalConceptExtraction,
  validateMinimalClinicalText,
  type ClinicalConceptExtractor,
  type ExtractedClinicalConcept,
} from "./clinical-nlp";
import type { ClinicalCodingCandidate } from "./clinical-coding-explorer-model";

export type AiAssistedCodingResult = {
  extractedConcepts: ExtractedClinicalConcept[];
  documentationQuestions: string[];
  candidates: ClinicalCodingCandidate[];
  model: { provider: string; modelId: string };
};

/**
 * AI is only a query-expansion layer. Every returned code must still come from
 * searchClinicalCodingCandidates(), which is backed by the active South African MIT release.
 */
export async function searchFromClinicalNarrative(
  supabase: SupabaseClient,
  minimalClinicalText: string,
  ctx: CodingSearchContext,
  extractor: ClinicalConceptExtractor,
): Promise<AiAssistedCodingResult> {
  const input = validateMinimalClinicalText(minimalClinicalText);
  const extraction = validateClinicalConceptExtraction(await extractor.extract({ minimalClinicalText: input }));
  const searchable = extraction.concepts.filter((x) => !x.negated && x.kind !== "context");

  const batches = await Promise.all(
    searchable.map((concept) => searchClinicalCodingCandidates(supabase, concept.term, { ...ctx, limit: 6 })),
  );

  const deduped = new Map<string, ClinicalCodingCandidate>();
  for (const batch of batches) {
    for (const candidate of batch) {
      if (!deduped.has(candidate.codeId)) deduped.set(candidate.codeId, candidate);
    }
  }

  return {
    extractedConcepts: extraction.concepts,
    documentationQuestions: extraction.documentationQuestions,
    candidates: [...deduped.values()].slice(0, ctx.limit ?? 12),
    model: { provider: extractor.provider, modelId: extractor.modelId },
  };
}
