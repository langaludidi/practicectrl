/**
 * Maps an official South African ICD-10 MIT spreadsheet row into the canonical Phase 1 shape.
 * The column names follow the NDoH published MIT file-layout document.
 * This mapper does not decide clinical validity; it preserves the official flags.
 */

export type MitRawRow = Record<string, unknown>;

export type CanonicalMitRow = {
  mit_number: string | null;
  chapter_no: string | null;
  chapter_desc: string | null;
  group_code: string | null;
  group_desc: string | null;
  icd10_3_code: string | null;
  icd10_3_code_desc: string | null;
  code: string;
  normalized_code: string;
  official_description: string;
  valid_clinical_use: boolean;
  valid_primary: boolean;
  valid_asterisk: boolean;
  valid_dagger: boolean;
  valid_sequelae: boolean;
  age_range: string | null;
  gender: "M" | "F" | "U" | null;
  sa_status: string | null;
  who_start_date: string | null;
  who_end_date: string | null;
  who_revision_history: string | null;
  sa_start_date: string | null;
  sa_end_date: string | null;
  sa_revision_history: string | null;
  official_comment: string | null;
};

const asText = (value: unknown): string | null => {
  if (value === null || value === undefined) return null;
  const s = String(value).trim();
  return s.length ? s : null;
};

const yesNo = (value: unknown, field: string): boolean => {
  const s = String(value ?? "").trim().toUpperCase();
  if (s === "Y") return true;
  if (s === "N") return false;
  throw new Error(`${field}: expected Y/N, received ${JSON.stringify(value)}`);
};

const yyyymmdd = (value: unknown, field: string): string | null => {
  const s = asText(value);
  if (!s) return null;
  if (!/^\d{8}$/.test(s)) throw new Error(`${field}: expected CCYYMMDD, received ${JSON.stringify(value)}`);
  const iso = `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;
  const d = new Date(`${iso}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== iso) {
    throw new Error(`${field}: invalid date ${s}`);
  }
  return iso;
};

const normalizeCode = (code: string) => code.toUpperCase().replace(/[^A-Z0-9*]/g, "");

export function mapMitRow(row: MitRawRow): CanonicalMitRow {
  const code = asText(row.ICD10_Code);
  const description = asText(row.WHO_Full_Desc);
  if (!code) throw new Error("ICD10_Code is required");
  if (!description) throw new Error(`WHO_Full_Desc is required for ${code}`);

  const genderRaw = asText(row.Gender)?.toUpperCase() ?? null;
  if (genderRaw !== null && !["M", "F", "U"].includes(genderRaw)) {
    throw new Error(`Gender: unexpected value ${genderRaw} for ${code}`);
  }

  return {
    mit_number: asText(row.Number),
    chapter_no: asText(row.Chapter_No),
    chapter_desc: asText(row.Chapter_Desc),
    group_code: asText(row.Group_Code),
    group_desc: asText(row.Group_Desc),
    icd10_3_code: asText(row.ICD10_3_Code),
    icd10_3_code_desc: asText(row.ICD10_3_Code_Desc),
    code,
    normalized_code: normalizeCode(code),
    official_description: description,
    valid_clinical_use: yesNo(row.Valid_ICD10_ClinicalUse, "Valid_ICD10_ClinicalUse"),
    valid_primary: yesNo(row.Valid_ICD10_Primary, "Valid_ICD10_Primary"),
    valid_asterisk: yesNo(row.Valid_ICD10_Asterisk, "Valid_ICD10_Asterisk"),
    valid_dagger: yesNo(row.Valid_ICD10_Dagger, "Valid_ICD10_Dagger"),
    valid_sequelae: yesNo(row.Valid_ICD10_Sequelae, "Valid_ICD10_Sequelae"),
    age_range: asText(row.Age_Range),
    gender: genderRaw as CanonicalMitRow["gender"],
    sa_status: asText(row.Status),
    who_start_date: yyyymmdd(row.WHO_Start_Date, "WHO_Start_Date"),
    who_end_date: yyyymmdd(row.WHO_End_Date, "WHO_End_Date"),
    who_revision_history: asText(row.WHO_Revision_History),
    sa_start_date: yyyymmdd(row.SA_Start_Date, "SA_Start_Date"),
    sa_end_date: yyyymmdd(row.SA_End_Date, "SA_End_Date"),
    sa_revision_history: asText(row.SA_Revision_History),
    official_comment: asText(row.Comment),
  };
}

export const REQUIRED_MIT_COLUMNS = [
  "Number",
  "Chapter_No",
  "Chapter_Desc",
  "Group_Code",
  "Group_Desc",
  "ICD10_3_Code",
  "ICD10_3_Code_Desc",
  "ICD10_Code",
  "WHO_Full_Desc",
  "Valid_ICD10_ClinicalUse",
  "Valid_ICD10_Primary",
  "Valid_ICD10_Asterisk",
  "Valid_ICD10_Dagger",
  "Valid_ICD10_Sequelae",
  "Age_Range",
  "Gender",
  "Status",
  "WHO_Start_Date",
  "WHO_End_Date",
  "WHO_Revision_History",
  "SA_Start_Date",
  "SA_End_Date",
  "SA_Revision_History",
  "Comment",
] as const;

export function assertMitHeaders(headers: readonly string[]): void {
  const actual = new Set(headers.map((h) => h.trim()));
  const missing = REQUIRED_MIT_COLUMNS.filter((h) => !actual.has(h));
  if (missing.length) throw new Error(`MIT schema mismatch. Missing columns: ${missing.join(", ")}`);
}
