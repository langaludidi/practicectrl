import type { SupabaseClient } from "@supabase/supabase-js";

export type Icd10SearchResult = {
  id: string;
  code: string;
  official_description: string;
  valid_clinical_use: boolean;
  valid_primary: boolean;
  valid_asterisk: boolean;
  valid_dagger: boolean;
  valid_sequelae: boolean;
  age_range: string | null;
  gender: "M" | "F" | "U" | null;
  source_release_id: string;
  sa_start_date: string | null;
  sa_end_date: string | null;
  match_reason:
    | "exact_code"
    | "code_prefix"
    | "exact_description"
    | "exact_alias"
    | "full_text"
    | "fuzzy_description"
    | "fuzzy_alias";
  relevance: number;
};

export async function searchSaIcd10(
  supabase: SupabaseClient,
  query: string,
  options: { sourceReleaseId?: string; limit?: number } = {},
): Promise<Icd10SearchResult[]> {
  const q = query.trim();
  if (q.length < 2) return [];

  const { data, error } = await supabase.rpc("search_sa_icd10", {
    p_query: q,
    p_source_release_id: options.sourceReleaseId ?? null,
    p_limit: Math.min(Math.max(options.limit ?? 20, 1), 50),
  });

  if (error) throw error;
  return (data ?? []) as Icd10SearchResult[];
}
