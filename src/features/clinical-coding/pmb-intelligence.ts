import type { SupabaseClient } from "@supabase/supabase-js";

export type PmbRelationship = {
  id: string;
  source_release_id: string;
  icd10_code: string;
  pmb_category: string | null;
  dtp_number: string | null;
  cdl_condition: string | null;
  pmb_descriptor: string | null;
  qualification_notes: string | null;
  treatment_context: string | null;
};

export type PmbUiState =
  | { kind: "none"; label: "No PMB relationship identified" }
  | { kind: "possible"; label: "Possible PMB relationship"; mappings: PmbRelationship[] }
  | { kind: "unavailable"; label: "PMB information unavailable"; reason: string };

/**
 * This is a lookup, not PMB adjudication. The CMS coded list is guidance and does not
 * itself establish entitlement. The UI must keep the word "Possible" until a clinician
 * has reviewed the applicable descriptor/criteria.
 */
export async function getPossiblePmbRelationships(
  supabase: SupabaseClient,
  icd10Code: string,
  options: { sourceReleaseId?: string } = {},
): Promise<PmbUiState> {
  const { data, error } = await supabase.rpc("get_possible_pmb_relationships", {
    p_icd10_code: icd10Code,
    p_source_release_id: options.sourceReleaseId ?? null,
  });

  if (error) {
    return { kind: "unavailable", label: "PMB information unavailable", reason: error.message };
  }

  const mappings = (data ?? []) as PmbRelationship[];
  if (mappings.length === 0) return { kind: "none", label: "No PMB relationship identified" };
  return { kind: "possible", label: "Possible PMB relationship", mappings };
}
