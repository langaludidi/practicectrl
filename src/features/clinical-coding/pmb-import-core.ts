export type PmbCanonicalRow = {
  icd10_code: string;
  normalized_code: string;
  pmb_category: string | null;
  dtp_number: string | null;
  cdl_condition: string | null;
  pmb_descriptor: string | null;
  qualification_notes: string | null;
  treatment_context: string | null;
};

export type PmbColumnMap = {
  icd10Code: string;
  pmbCategory?: string;
  dtpNumber?: string;
  cdlCondition?: string;
  pmbDescriptor?: string;
  qualificationNotes?: string;
  treatmentContext?: string;
};

const normHeader = (x: string) => x.trim().toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const clean = (v: unknown) => String(v ?? "").trim();

const candidates: Record<keyof PmbColumnMap, string[]> = {
  icd10Code: ["icd 10 code", "icd10 code", "icd code", "code"],
  pmbCategory: ["pmb category", "category", "pmb type"],
  dtpNumber: ["dtp number", "dtp no", "dtp", "diagnosis treatment pair"],
  cdlCondition: ["cdl condition", "chronic disease list", "cdl"],
  pmbDescriptor: ["pmb descriptor", "descriptor", "diagnosis descriptor", "pmb description"],
  qualificationNotes: ["qualification notes", "qualification", "criteria", "notes"],
  treatmentContext: ["treatment context", "treatment", "treatment component"],
};

function findUniqueHeader(headers: string[], aliases: string[]): string | undefined {
  const aliasSet = new Set(aliases.map(normHeader));
  const matches = headers.filter((h) => aliasSet.has(normHeader(h)));
  if (matches.length > 1) throw new Error(`Ambiguous PMB column mapping: ${matches.join(", ")}`);
  return matches[0];
}

/**
 * Auto-detection is intentionally strict. CMS workbooks can change shape, so an unknown
 * workbook must stop at staging rather than silently guessing column semantics.
 */
export function detectPmbColumnMap(headers: string[]): PmbColumnMap {
  const icd10Code = findUniqueHeader(headers, candidates.icd10Code);
  if (!icd10Code) {
    throw new Error("Could not identify the ICD-10 code column. Supply an explicit PMB column map before import.");
  }

  return {
    icd10Code,
    pmbCategory: findUniqueHeader(headers, candidates.pmbCategory),
    dtpNumber: findUniqueHeader(headers, candidates.dtpNumber),
    cdlCondition: findUniqueHeader(headers, candidates.cdlCondition),
    pmbDescriptor: findUniqueHeader(headers, candidates.pmbDescriptor),
    qualificationNotes: findUniqueHeader(headers, candidates.qualificationNotes),
    treatmentContext: findUniqueHeader(headers, candidates.treatmentContext),
  };
}

export function mapPmbRow(row: Record<string, unknown>, map: PmbColumnMap): PmbCanonicalRow {
  const icd10 = clean(row[map.icd10Code]);
  if (!icd10) throw new Error("PMB row has no ICD-10 code");

  const get = (key?: string) => (key ? clean(row[key]) || null : null);
  return {
    icd10_code: icd10,
    normalized_code: icd10.toUpperCase().replace(/[^A-Z0-9*]+/g, ""),
    pmb_category: get(map.pmbCategory),
    dtp_number: get(map.dtpNumber),
    cdl_condition: get(map.cdlCondition),
    pmb_descriptor: get(map.pmbDescriptor),
    qualification_notes: get(map.qualificationNotes),
    treatment_context: get(map.treatmentContext),
  };
}
