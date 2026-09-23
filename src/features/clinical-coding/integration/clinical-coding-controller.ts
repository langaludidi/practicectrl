import type { SupabaseClient } from "@supabase/supabase-js";
import type { ClinicalCodingCandidate } from "../clinical-coding-explorer-model";
import { searchClinicalCodingCandidates, type CodingSearchContext } from "../coding-service";
import type { ValidationMessage } from "../deterministic-validation";

export type CodingSessionRecord = {
  id: string;
  practice_id: string;
  patient_id: string | null;
  encounter_id: string | null;
  actor_user_id: string;
  service_date: string;
  patient_sex: "M" | "F" | "U" | null;
  mit_release_id: string;
  phisc_release_id: string | null;
  cms_release_id: string | null;
  status: "open" | "completed" | "cancelled";
};

export type StartCodingSessionInput = {
  practiceId: string;
  patientId?: string | null;
  encounterId?: string | null;
  serviceDate: string;
  patientSex?: "M" | "F" | "U" | null;
  mitReleaseId?: string;
  phiscReleaseId?: string | null;
  cmsReleaseId?: string | null;
  sourceContextHash?: string | null;
};

async function requireUserId(supabase: SupabaseClient): Promise<string> {
  const { data, error } = await supabase.auth.getUser();
  if (error) throw error;
  if (!data.user) throw new Error("Authentication required");
  return data.user.id;
}

async function resolveActiveSourceRelease(
  supabase: SupabaseClient,
  authority: "NDOH" | "CMS" | "PHISC",
  sourceName?: string,
): Promise<string | null> {
  let query = supabase
    .from("coding_source_release")
    .select("id")
    .eq("authority", authority)
    .eq("status", "active")
    .order("published_date", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false })
    .limit(1);
  if (sourceName) query = query.eq("source_name", sourceName);
  const { data, error } = await query.maybeSingle();
  if (error) throw error;
  return data?.id ?? null;
}

export async function startCodingSession(
  supabase: SupabaseClient,
  input: StartCodingSessionInput,
): Promise<CodingSessionRecord> {
  const userId = await requireUserId(supabase);

  const mitReleaseId = input.mitReleaseId ?? await resolveActiveSourceRelease(
    supabase,
    "NDOH",
    "ICD-10 Master Industry Table",
  );
  if (!mitReleaseId) throw new Error("No active South African MIT release is available");

  const [phiscReleaseId, cmsReleaseId] = await Promise.all([
    input.phiscReleaseId === undefined
      ? resolveActiveSourceRelease(supabase, "PHISC")
      : Promise.resolve(input.phiscReleaseId),
    input.cmsReleaseId === undefined
      ? resolveActiveSourceRelease(supabase, "CMS")
      : Promise.resolve(input.cmsReleaseId),
  ]);

  const { data, error } = await supabase
    .from("coding_session")
    .insert({
      practice_id: input.practiceId,
      patient_id: input.patientId ?? null,
      encounter_id: input.encounterId ?? null,
      actor_user_id: userId,
      service_date: input.serviceDate,
      patient_sex: input.patientSex ?? null,
      mit_release_id: mitReleaseId,
      phisc_release_id: phiscReleaseId,
      cms_release_id: cmsReleaseId,
      source_context_hash: input.sourceContextHash ?? null,
      status: "open",
    })
    .select("id,practice_id,patient_id,encounter_id,actor_user_id,service_date,patient_sex,mit_release_id,phisc_release_id,cms_release_id,status")
    .single();

  if (error) throw error;
  return data as CodingSessionRecord;
}

function sourceReleaseSnapshot(session: CodingSessionRecord, candidate: ClinicalCodingCandidate) {
  const pmbReleaseIds = candidate.pmb.kind === "possible"
    ? [...new Set(candidate.pmb.mappings.map((x) => x.source_release_id))]
    : [];

  return {
    mit_release_id: session.mit_release_id,
    phisc_release_id: session.phisc_release_id,
    cms_release_id: session.cms_release_id,
    pmb_mapping_release_ids: pmbReleaseIds,
  };
}

async function persistValidationMessages(
  supabase: SupabaseClient,
  session: CodingSessionRecord,
  candidate: ClinicalCodingCandidate,
  messages: ValidationMessage[],
): Promise<void> {
  if (messages.length === 0) return;
  const userId = await requireUserId(supabase);

  const rows = messages.map((warning) => ({
    practice_id: session.practice_id,
    actor_user_id: userId,
    encounter_id: session.encounter_id,
    coding_session_id: session.id,
    code_id: candidate.codeId,
    coding_rule_id: null,
    rule_code: warning.ruleCode,
    severity: warning.severity,
    message: warning.message,
    status: "open",
    source_context: {
      deterministic: true,
      source_release_id: candidate.sourceReleaseId,
    },
  }));

  const { error } = await supabase.from("coding_validation_event").insert(rows);
  if (error) throw error;
}

async function snapshotCandidates(
  supabase: SupabaseClient,
  session: CodingSessionRecord,
  candidates: ClinicalCodingCandidate[],
): Promise<void> {
  if (candidates.length === 0) return;
  const userId = await requireUserId(supabase);
  const rows = candidates.map((candidate, index) => ({
    coding_session_id: session.id,
    practice_id: session.practice_id,
    actor_user_id: userId,
    code_id: candidate.codeId,
    rank: index + 1,
    match_reason: candidate.matchLabel,
    relevance: null,
    warning_snapshot: candidate.warnings,
    pmb_snapshot: candidate.pmb,
    source_release_ids: sourceReleaseSnapshot(session, candidate),
  }));
  const { error } = await supabase.from("coding_candidate_snapshot").insert(rows);
  if (error) throw error;
}

export async function searchWithinCodingSession(
  supabase: SupabaseClient,
  session: CodingSessionRecord,
  query: string,
  input: {
    targetPosition: "primary" | "secondary";
    existingCodes?: CodingSearchContext["existingCodes"];
    limit?: number;
  },
): Promise<ClinicalCodingCandidate[]> {
  if (session.status !== "open") throw new Error("Coding session is not open");

  const candidates = await searchClinicalCodingCandidates(supabase, query, {
    serviceDate: session.service_date,
    patientSex: session.patient_sex,
    targetPosition: input.targetPosition,
    existingCodes: input.existingCodes,
    sourceReleaseId: session.mit_release_id,
    pmbSourceReleaseId: session.cms_release_id ?? undefined,
    limit: input.limit ?? 12,
  });

  await snapshotCandidates(supabase, session, candidates);
  await Promise.all(candidates.map((candidate) =>
    persistValidationMessages(supabase, session, candidate, candidate.warnings),
  ));

  return candidates;
}

export async function confirmCodingCandidate(
  supabase: SupabaseClient,
  input: {
    sessionId: string;
    codeId: string;
    position: "primary" | "secondary";
    sequenceNo?: number;
    decision?: "ACCEPTED" | "MANUALLY_SELECTED" | "REPLACED";
    decisionReason?: string | null;
  },
): Promise<string> {
  const { data, error } = await supabase.rpc("confirm_coding_decision", {
    p_coding_session_id: input.sessionId,
    p_code_id: input.codeId,
    p_position: input.position,
    p_sequence_no: input.sequenceNo ?? 1,
    p_decision: input.decision ?? "ACCEPTED",
    p_decision_reason: input.decisionReason ?? null,
  });
  if (error) throw error;
  if (!data) throw new Error("Coding decision confirmation returned no decision id");
  return data as string;
}

export async function recordRejectedCandidate(
  supabase: SupabaseClient,
  input: {
    session: CodingSessionRecord;
    codeId: string;
    position: "primary" | "secondary";
    reason?: string | null;
  },
): Promise<string> {
  const userId = await requireUserId(supabase);
  const { data, error } = await supabase
    .from("coding_decision")
    .insert({
      coding_session_id: input.session.id,
      practice_id: input.session.practice_id,
      code_id: input.codeId,
      decision: "REJECTED",
      position: input.position,
      sequence_no: 1,
      decision_reason: input.reason ?? null,
      selected_by: userId,
    })
    .select("id")
    .single();
  if (error) throw error;
  return data.id as string;
}

export async function recordConfidentialityEvent(
  supabase: SupabaseClient,
  input: {
    session: CodingSessionRecord;
    requestType: "patient_refusal" | "provider_refusal";
    informationExplained: boolean;
    financialImplicationsExplained: boolean;
    consentOrInstructionRecorded: boolean;
    supportingNoteReference?: string | null;
  },
): Promise<string> {
  const userId = await requireUserId(supabase);
  const { data, error } = await supabase
    .from("coding_confidentiality_event")
    .insert({
      coding_session_id: input.session.id,
      practice_id: input.session.practice_id,
      patient_id: input.session.patient_id,
      encounter_id: input.session.encounter_id,
      request_type: input.requestType,
      information_explained: input.informationExplained,
      financial_implications_explained: input.financialImplicationsExplained,
      consent_or_instruction_recorded: input.consentOrInstructionRecorded,
      supporting_note_reference: input.supportingNoteReference ?? null,
      actor_user_id: userId,
    })
    .select("id")
    .single();
  if (error) throw error;
  return data.id as string;
}

export async function completeCodingSession(
  supabase: SupabaseClient,
  sessionId: string,
): Promise<void> {
  const { error } = await supabase
    .from("coding_session")
    .update({ status: "completed", completed_at: new Date().toISOString() })
    .eq("id", sessionId);
  if (error) throw error;
}
