import type { SupabaseClient } from "@supabase/supabase-js";
import { assertMitHeaders, mapMitRow, type MitRawRow } from "./mit-mapper";

export type MitImportSummary = {
  received: number;
  valid: number;
  rejected: number;
  errors: Array<{ row: number; message: string }>;
};

/**
 * Hash the untouched source bytes before parsing. Store this hash in coding_source_release.
 */
export async function sha256Source(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Strictly validate and map already-parsed worksheet rows.
 * Parsing XLSX/CSV is intentionally kept outside this function so the source adapter can be swapped
 * without altering clinical coding logic.
 */
export function validateMitRows(rows: MitRawRow[]): {
  mapped: ReturnType<typeof mapMitRow>[];
  summary: MitImportSummary;
} {
  if (!rows.length) {
    return { mapped: [], summary: { received: 0, valid: 0, rejected: 0, errors: [] } };
  }

  assertMitHeaders(Object.keys(rows[0]));

  const mapped: ReturnType<typeof mapMitRow>[] = [];
  const errors: Array<{ row: number; message: string }> = [];

  rows.forEach((row, i) => {
    try {
      mapped.push(mapMitRow(row));
    } catch (error) {
      errors.push({ row: i + 2, message: error instanceof Error ? error.message : String(error) });
    }
  });

  return {
    mapped,
    summary: {
      received: rows.length,
      valid: mapped.length,
      rejected: errors.length,
      errors,
    },
  };
}

/**
 * Trusted-server-only persistence helper. Never call with a browser Supabase client.
 * This inserts canonical rows for a pre-created source release; release activation remains a
 * separate, reviewed administrative step.
 */
export async function persistMitBatch(
  admin: SupabaseClient,
  sourceReleaseId: string,
  rows: ReturnType<typeof mapMitRow>[],
  chunkSize = 500,
): Promise<void> {
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize).map((row) => ({
      ...row,
      source_release_id: sourceReleaseId,
    }));

    const { error } = await admin.from("sa_icd10_code").insert(chunk);
    if (error) throw error;
  }
}
