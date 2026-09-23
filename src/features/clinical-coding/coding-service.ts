import type { SupabaseClient } from "@supabase/supabase-js";
import { searchSaIcd10, type Icd10SearchResult } from "./coding-search";
import { toCandidateCard } from "./coding-ui-contract";
import { validateMitCode, type Sex, type ValidationMessage } from "./deterministic-validation";
import { evaluateMachineRules, SOUTH_AFRICAN_BASE_RULES, type SelectedCode } from "./rule-engine";
import { getPossiblePmbRelationships } from "./pmb-intelligence";
import { canConfirmCandidate, type ClinicalCodingCandidate } from "./clinical-coding-explorer-model";

export type CodingSearchContext = {
  serviceDate: string; // YYYY-MM-DD
  patientSex: Sex;
  targetPosition: "primary" | "secondary";
  existingCodes?: SelectedCode[];
  sourceReleaseId?: string;
  pmbSourceReleaseId?: string;
  limit?: number;
};

const normalizeCode = (code: string) => code.toUpperCase().replace(/[^A-Z0-9*]+/g, "");

function validateCandidate(result: Icd10SearchResult, ctx: CodingSearchContext): ValidationMessage[] {
  const mit = validateMitCode(
    {
      code: result.code,
      validClinicalUse: result.valid_clinical_use,
      validPrimary: result.valid_primary,
      validAsterisk: result.valid_asterisk,
      validDagger: result.valid_dagger,
      gender: result.gender,
      saStartDate: result.sa_start_date,
      saEndDate: result.sa_end_date,
    },
    { position: ctx.targetPosition, patientSex: ctx.patientSex, serviceDate: ctx.serviceDate },
  );

  const current: SelectedCode = {
    code: result.code,
    normalizedCode: normalizeCode(result.code),
    position: ctx.targetPosition,
    validAsterisk: result.valid_asterisk,
    validDagger: result.valid_dagger,
    validSequelae: result.valid_sequelae,
  };
  const selectedCodes = [...(ctx.existingCodes ?? []), current];
  const relational = evaluateMachineRules(SOUTH_AFRICAN_BASE_RULES, { selectedCodes, currentCode: current });

  const seen = new Set<string>();
  return [...mit, ...relational].filter((x) => {
    const key = `${x.ruleCode}:${x.message}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * Application orchestration boundary: deterministic ICD retrieval and validation first,
 * PMB enrichment second. No AI is required for this service to function.
 */
export async function searchClinicalCodingCandidates(
  supabase: SupabaseClient,
  query: string,
  ctx: CodingSearchContext,
): Promise<ClinicalCodingCandidate[]> {
  const results = await searchSaIcd10(supabase, query, {
    sourceReleaseId: ctx.sourceReleaseId,
    limit: ctx.limit ?? 12,
  });

  return Promise.all(results.map(async (result) => {
    const warnings = validateCandidate(result, ctx);
    const base = toCandidateCard(result, warnings);
    const pmb = await getPossiblePmbRelationships(supabase, result.code, {
      sourceReleaseId: ctx.pmbSourceReleaseId,
    });

    return {
      ...base,
      pmb,
      sourceLabel: "National Department of Health — South African ICD-10 Master Industry Table",
      canConfirm: canConfirmCandidate(base),
    } satisfies ClinicalCodingCandidate;
  }));
}
