-- Recovered medicines schema from the connected project's catalog.
-- Historical validator migrations omitted the original table DDL. No patient data is copied.
begin;

create table public."medication_reconciliation_item" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "session_id" uuid not null,
  "existing_medication_id" uuid,
  "product_id" uuid,
  "ingredient_id" uuid,
  "medication_name" text not null,
  "dose_text" text,
  "route" text,
  "frequency" text,
  "proposed_action" text default 'confirm'::text not null,
  "source" text default 'manual'::text not null,
  "confidence" text,
  "evidence_text" text,
  "review_status" text default 'pending'::text not null,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null
);

create table public."medication_reconciliation_session" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "encounter_id" uuid,
  "status" text default 'open'::text not null,
  "source_context" text,
  "started_by" uuid not null,
  "started_at" timestamp with time zone default now() not null,
  "completed_by" uuid,
  "completed_at" timestamp with time zone,
  "updated_at" timestamp with time zone default now() not null
);

create table public."medicine_interaction_rule" (
  "id" uuid default gen_random_uuid() not null,
  "source_release_id" uuid not null,
  "ingredient_a_id" uuid not null,
  "ingredient_b_id" uuid not null,
  "severity" text not null,
  "title" text not null,
  "description" text not null,
  "management_text" text,
  "evidence_reference" text,
  "active" boolean default true not null,
  "effective_from" date,
  "effective_to" date,
  "created_at" timestamp with time zone default now() not null
);

create table public."medicine_product_ingredient" (
  "product_id" uuid not null,
  "ingredient_id" uuid not null,
  "strength_text" text,
  "sequence_no" integer default 1 not null
);

create table public."medicine_reference_ingredient" (
  "id" uuid default gen_random_uuid() not null,
  "source_release_id" uuid,
  "canonical_key" text not null,
  "generic_name" text not null,
  "atc_code" text,
  "schedule_text" text,
  "active" boolean default true not null,
  "effective_from" date,
  "effective_to" date,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."medicine_reference_product" (
  "id" uuid default gen_random_uuid() not null,
  "source_release_id" uuid,
  "nappi_code" text,
  "sahpra_registration_no" text,
  "product_name" text not null,
  "proprietary_name" text,
  "active_ingredient_text" text,
  "strength_text" text,
  "dosage_form" text,
  "route_text" text,
  "schedule_text" text,
  "manufacturer" text,
  "pack_size" text,
  "status" text default 'unknown'::text not null,
  "effective_from" date,
  "effective_to" date,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."medicines_ai_review" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "prescription_id" uuid,
  "reconciliation_session_id" uuid,
  "capability_key" text not null,
  "provider_config_id" uuid not null,
  "status" text default 'requested'::text not null,
  "input_mode" text default 'structured'::text not null,
  "input_sha256" text not null,
  "model_id" text not null,
  "summary" text,
  "structured_output" jsonb default '{}'::jsonb not null,
  "limitations" jsonb default '[]'::jsonb not null,
  "confidence" text,
  "provider_output_sha256" text,
  "created_by" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "completed_at" timestamp with time zone,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "error_code" text,
  "error_detail" text,
  "applied_by" uuid,
  "applied_at" timestamp with time zone
);

create table public."medicines_ai_review_source" (
  "review_id" uuid not null,
  "source_file_id" uuid not null,
  "content_type" text,
  "sha256" text,
  "source_index" integer not null
);

create table public."medicines_ai_source_file" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "reconciliation_session_id" uuid,
  "prescription_id" uuid,
  "storage_path" text not null,
  "original_filename" text,
  "content_type" text not null,
  "sha256" text,
  "created_by" uuid not null,
  "created_at" timestamp with time zone default now() not null
);

create table public."patient_allergy" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "ingredient_id" uuid,
  "substance_text" text not null,
  "reaction_text" text,
  "severity" text default 'unknown'::text not null,
  "status" text default 'active'::text not null,
  "source" text default 'clinical'::text not null,
  "recorded_by" uuid,
  "recorded_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."patient_medication" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "product_id" uuid,
  "ingredient_id" uuid,
  "medication_name" text not null,
  "dose_text" text,
  "route" text,
  "frequency" text,
  "duration_text" text,
  "indication_text" text,
  "status" text default 'active'::text not null,
  "start_date" date,
  "end_date" date,
  "source" text default 'clinical'::text not null,
  "external_ref" text,
  "reconciled" boolean default false not null,
  "reconciled_by" uuid,
  "reconciled_at" timestamp with time zone,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."prescription" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "encounter_id" uuid,
  "status" text default 'draft'::text not null,
  "issue_mode" text default 'internal_draft'::text not null,
  "provider_id" uuid,
  "interface_id" uuid,
  "connection_id" uuid,
  "indication_text" text,
  "general_instructions" text,
  "prescriber_user_id" uuid not null,
  "created_by" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "safety_assessed_at" timestamp with time zone,
  "clinician_approved_at" timestamp with time zone,
  "external_prescription_ref" text,
  "external_signature_reference" text,
  "transmitted_at" timestamp with time zone,
  "cancelled_at" timestamp with time zone,
  "cancellation_reason" text
);

create table public."prescription_item" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "prescription_id" uuid not null,
  "product_id" uuid,
  "ingredient_id" uuid,
  "medication_name" text not null,
  "nappi_code_snapshot" text,
  "dose_value" numeric,
  "dose_unit" text,
  "route" text,
  "frequency" text,
  "duration_text" text,
  "quantity" numeric,
  "quantity_unit" text,
  "repeats" integer default 0 not null,
  "prn" boolean default false not null,
  "instructions" text,
  "source" text default 'manual'::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."prescription_safety_assessment" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "prescription_id" uuid not null,
  "assessment_version" integer default 1 not null,
  "status" text not null,
  "blocking_count" integer default 0 not null,
  "warning_count" integer default 0 not null,
  "reference_ready" boolean default false not null,
  "interaction_data_ready" boolean default false not null,
  "assessed_by" uuid not null,
  "assessed_at" timestamp with time zone default now() not null,
  "input_sha256" text not null
);

create table public."prescription_safety_finding" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "assessment_id" uuid not null,
  "prescription_item_id" uuid,
  "finding_type" text not null,
  "severity" text not null,
  "code" text not null,
  "title" text not null,
  "detail" text not null,
  "source_rule_id" uuid,
  "deterministic" boolean default true not null,
  "created_at" timestamp with time zone default now() not null
);

create table public."prescription_transmission_event" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "transmission_request_id" uuid not null,
  "event_type" text not null,
  "detail" text,
  "provider_event_ref" text,
  "occurred_at" timestamp with time zone default now() not null
);

create table public."prescription_transmission_request" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "prescription_id" uuid not null,
  "provider_id" uuid not null,
  "interface_id" uuid not null,
  "connection_id" uuid not null,
  "environment" text not null,
  "status" text default 'queued'::text not null,
  "idempotency_key" text not null,
  "queued_by" uuid not null,
  "queued_at" timestamp with time zone default now() not null,
  "submitted_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "external_reference" text,
  "error_code" text,
  "error_detail" text
);

alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_confidence_check" CHECK (((confidence IS NULL) OR (confidence = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text]))));
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_pkey" PRIMARY KEY (id);
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_proposed_action_check" CHECK ((proposed_action = ANY (ARRAY['confirm'::text, 'add'::text, 'change'::text, 'stop'::text, 'unable_to_verify'::text])));
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_review_status_check" CHECK ((review_status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text])));
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_source_check" CHECK ((source = ANY (ARRAY['manual'::text, 'ai_extracted'::text, 'document'::text, 'patient_reported'::text, 'import'::text])));
alter table public."medication_reconciliation_session" add constraint "medication_reconciliation_session_pkey" PRIMARY KEY (id);
alter table public."medication_reconciliation_session" add constraint "medication_reconciliation_session_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'reviewing'::text, 'completed'::text, 'cancelled'::text])));
alter table public."medicine_interaction_rule" add constraint "medicine_interaction_rule_check" CHECK ((ingredient_a_id <> ingredient_b_id));
alter table public."medicine_interaction_rule" add constraint "medicine_interaction_rule_check1" CHECK (((effective_to IS NULL) OR (effective_from IS NULL) OR (effective_to >= effective_from)));
alter table public."medicine_interaction_rule" add constraint "medicine_interaction_rule_pkey" PRIMARY KEY (id);
alter table public."medicine_interaction_rule" add constraint "medicine_interaction_rule_severity_check" CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'major'::text, 'contraindicated'::text])));
alter table public."medicine_product_ingredient" add constraint "medicine_product_ingredient_pkey" PRIMARY KEY (product_id, ingredient_id);
alter table public."medicine_product_ingredient" add constraint "medicine_product_ingredient_sequence_no_check" CHECK (((sequence_no >= 1) AND (sequence_no <= 20)));
alter table public."medicine_reference_ingredient" add constraint "medicine_reference_ingredient_canonical_key_check" CHECK ((canonical_key ~ '^[a-z0-9][a-z0-9._-]{1,159}$'::text));
alter table public."medicine_reference_ingredient" add constraint "medicine_reference_ingredient_canonical_key_key" UNIQUE (canonical_key);
alter table public."medicine_reference_ingredient" add constraint "medicine_reference_ingredient_check" CHECK (((effective_to IS NULL) OR (effective_from IS NULL) OR (effective_to >= effective_from)));
alter table public."medicine_reference_ingredient" add constraint "medicine_reference_ingredient_pkey" PRIMARY KEY (id);
alter table public."medicine_reference_product" add constraint "medicine_reference_product_check" CHECK (((effective_to IS NULL) OR (effective_from IS NULL) OR (effective_to >= effective_from)));
alter table public."medicine_reference_product" add constraint "medicine_reference_product_pkey" PRIMARY KEY (id);
alter table public."medicine_reference_product" add constraint "medicine_reference_product_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'withdrawn'::text, 'unknown'::text])));
alter table public."medicines_ai_review" add constraint "medicines_ai_review_check1" CHECK (((status <> 'clinician_accepted'::text) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
alter table public."medicines_ai_review" add constraint "medicines_ai_review_confidence_check" CHECK (((confidence IS NULL) OR (confidence = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text]))));
alter table public."medicines_ai_review" add constraint "medicines_ai_review_input_mode_check" CHECK ((input_mode = ANY (ARRAY['structured'::text, 'document'::text, 'image'::text, 'mixed'::text])));
alter table public."medicines_ai_review" add constraint "medicines_ai_review_input_sha256_check" CHECK ((input_sha256 ~ '^[a-f0-9]{64}$'::text));
alter table public."medicines_ai_review" add constraint "medicines_ai_review_pkey" PRIMARY KEY (id);
alter table public."medicines_ai_review" add constraint "medicines_ai_review_provider_output_sha256_check" CHECK (((provider_output_sha256 IS NULL) OR (provider_output_sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."medicines_ai_review" add constraint "medicines_ai_review_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'processing'::text, 'completed'::text, 'failed'::text, 'clinician_accepted'::text, 'discarded'::text])));
alter table public."medicines_ai_review_source" add constraint "medicines_ai_review_source_pkey" PRIMARY KEY (review_id, source_file_id);
alter table public."medicines_ai_review_source" add constraint "medicines_ai_review_source_review_id_source_index_key" UNIQUE (review_id, source_index);
alter table public."medicines_ai_review_source" add constraint "medicines_ai_review_source_sha256_check" CHECK (((sha256 IS NULL) OR (sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."medicines_ai_review_source" add constraint "medicines_ai_review_source_source_index_check" CHECK (((source_index >= 1) AND (source_index <= 5)));
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_check" CHECK (((reconciliation_session_id IS NOT NULL) OR (prescription_id IS NOT NULL)));
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_check1" CHECK ((storage_path ~~ ((practice_id)::text || '/%'::text)));
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_content_type_check" CHECK ((content_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text])));
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_pkey" PRIMARY KEY (id);
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_sha256_check" CHECK (((sha256 IS NULL) OR (sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_storage_path_key" UNIQUE (storage_path);
alter table public."patient_allergy" add constraint "patient_allergy_pkey" PRIMARY KEY (id);
alter table public."patient_allergy" add constraint "patient_allergy_severity_check" CHECK ((severity = ANY (ARRAY['mild'::text, 'moderate'::text, 'severe'::text, 'life_threatening'::text, 'unknown'::text])));
alter table public."patient_allergy" add constraint "patient_allergy_source_check" CHECK ((source = ANY (ARRAY['clinical'::text, 'patient_reported'::text, 'document'::text, 'import'::text, 'other'::text])));
alter table public."patient_allergy" add constraint "patient_allergy_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'entered_in_error'::text])));
alter table public."patient_medication" add constraint "patient_medication_check" CHECK (((end_date IS NULL) OR (start_date IS NULL) OR (end_date >= start_date)));
alter table public."patient_medication" add constraint "patient_medication_pkey" PRIMARY KEY (id);
alter table public."patient_medication" add constraint "patient_medication_source_check" CHECK ((source = ANY (ARRAY['clinical'::text, 'patient_reported'::text, 'prescription'::text, 'reconciliation'::text, 'document'::text, 'import'::text, 'other'::text])));
alter table public."patient_medication" add constraint "patient_medication_status_check" CHECK ((status = ANY (ARRAY['proposed'::text, 'active'::text, 'held'::text, 'completed'::text, 'stopped'::text, 'entered_in_error'::text])));
alter table public."prescription" add constraint "prescription_issue_mode_check" CHECK ((issue_mode = ANY (ARRAY['internal_draft'::text, 'electronic'::text])));
alter table public."prescription" add constraint "prescription_pkey" PRIMARY KEY (id);
alter table public."prescription" add constraint "prescription_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'safety_review'::text, 'blocked'::text, 'clinician_approved'::text, 'transmission_pending'::text, 'transmitted'::text, 'accepted'::text, 'dispensed'::text, 'cancelled'::text, 'failed'::text])));
alter table public."prescription_item" add constraint "prescription_item_dose_value_check" CHECK (((dose_value IS NULL) OR (dose_value > (0)::numeric)));
alter table public."prescription_item" add constraint "prescription_item_pkey" PRIMARY KEY (id);
alter table public."prescription_item" add constraint "prescription_item_quantity_check" CHECK (((quantity IS NULL) OR (quantity > (0)::numeric)));
alter table public."prescription_item" add constraint "prescription_item_repeats_check" CHECK (((repeats >= 0) AND (repeats <= 12)));
alter table public."prescription_item" add constraint "prescription_item_source_check" CHECK ((source = ANY (ARRAY['manual'::text, 'ai_structured'::text, 'reconciliation'::text])));
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessmen_prescription_id_assessment_ve_key" UNIQUE (prescription_id, assessment_version);
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_assessment_version_check" CHECK ((assessment_version >= 1));
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_blocking_count_check" CHECK ((blocking_count >= 0));
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_input_sha256_check" CHECK ((input_sha256 ~ '^[a-f0-9]{64}$'::text));
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_pkey" PRIMARY KEY (id);
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_status_check" CHECK ((status = ANY (ARRAY['pass'::text, 'warning'::text, 'block'::text])));
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_warning_count_check" CHECK ((warning_count >= 0));
alter table public."prescription_safety_finding" add constraint "prescription_safety_finding_finding_type_check" CHECK ((finding_type = ANY (ARRAY['reference_data'::text, 'allergy'::text, 'interaction'::text, 'duplicate_therapy'::text, 'missing_field'::text, 'schedule'::text, 'monitoring'::text, 'other'::text])));
alter table public."prescription_safety_finding" add constraint "prescription_safety_finding_pkey" PRIMARY KEY (id);
alter table public."prescription_safety_finding" add constraint "prescription_safety_finding_severity_check" CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'blocking'::text])));
alter table public."prescription_transmission_event" add constraint "prescription_transmission_event_event_type_check" CHECK ((event_type = ANY (ARRAY['queued'::text, 'submitted'::text, 'accepted'::text, 'rejected'::text, 'failed'::text, 'cancelled'::text, 'dispensed'::text])));
alter table public."prescription_transmission_event" add constraint "prescription_transmission_event_pkey" PRIMARY KEY (id);
alter table public."prescription_transmission_request" add constraint "prescription_transmission_req_prescription_id_environment_i_key" UNIQUE (prescription_id, environment, idempotency_key);
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_environment_check" CHECK ((environment = ANY (ARRAY['sandbox'::text, 'production'::text])));
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_pkey" PRIMARY KEY (id);
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'submitted'::text, 'accepted'::text, 'rejected'::text, 'failed'::text, 'cancelled'::text])));

alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_existing_medication_id_fkey" FOREIGN KEY (existing_medication_id) REFERENCES patient_medication(id) ON DELETE SET NULL;
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_ingredient_id_fkey" FOREIGN KEY (ingredient_id) REFERENCES medicine_reference_ingredient(id) ON DELETE SET NULL;
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_product_id_fkey" FOREIGN KEY (product_id) REFERENCES medicine_reference_product(id) ON DELETE SET NULL;
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."medication_reconciliation_item" add constraint "medication_reconciliation_item_session_id_fkey" FOREIGN KEY (session_id) REFERENCES medication_reconciliation_session(id) ON DELETE CASCADE;
alter table public."medication_reconciliation_session" add constraint "medication_reconciliation_session_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."medication_reconciliation_session" add constraint "medication_reconciliation_session_encounter_id_fkey" FOREIGN KEY (encounter_id) REFERENCES practice_encounter(id) ON DELETE SET NULL;
alter table public."medication_reconciliation_session" add constraint "medication_reconciliation_session_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE CASCADE;
alter table public."medication_reconciliation_session" add constraint "medication_reconciliation_session_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."medication_reconciliation_session" add constraint "medication_reconciliation_session_started_by_fkey" FOREIGN KEY (started_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."medicine_interaction_rule" add constraint "medicine_interaction_rule_ingredient_a_id_fkey" FOREIGN KEY (ingredient_a_id) REFERENCES medicine_reference_ingredient(id) ON DELETE RESTRICT;
alter table public."medicine_interaction_rule" add constraint "medicine_interaction_rule_ingredient_b_id_fkey" FOREIGN KEY (ingredient_b_id) REFERENCES medicine_reference_ingredient(id) ON DELETE RESTRICT;
alter table public."medicine_interaction_rule" add constraint "medicine_interaction_rule_source_release_id_fkey" FOREIGN KEY (source_release_id) REFERENCES source_dataset_release(id) ON DELETE RESTRICT;
alter table public."medicine_product_ingredient" add constraint "medicine_product_ingredient_ingredient_id_fkey" FOREIGN KEY (ingredient_id) REFERENCES medicine_reference_ingredient(id) ON DELETE RESTRICT;
alter table public."medicine_product_ingredient" add constraint "medicine_product_ingredient_product_id_fkey" FOREIGN KEY (product_id) REFERENCES medicine_reference_product(id) ON DELETE CASCADE;
alter table public."medicine_reference_ingredient" add constraint "medicine_reference_ingredient_source_release_id_fkey" FOREIGN KEY (source_release_id) REFERENCES source_dataset_release(id) ON DELETE RESTRICT;
alter table public."medicine_reference_product" add constraint "medicine_reference_product_source_release_id_fkey" FOREIGN KEY (source_release_id) REFERENCES source_dataset_release(id) ON DELETE RESTRICT;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_applied_by_fkey" FOREIGN KEY (applied_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_capability_key_fkey" FOREIGN KEY (capability_key) REFERENCES assist_capability(capability_key) ON DELETE RESTRICT;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_prescription_id_fkey" FOREIGN KEY (prescription_id) REFERENCES prescription(id) ON DELETE CASCADE;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_provider_config_id_fkey" FOREIGN KEY (provider_config_id) REFERENCES assist_provider_config(id) ON DELETE RESTRICT;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_reconciliation_session_id_fkey" FOREIGN KEY (reconciliation_session_id) REFERENCES medication_reconciliation_session(id) ON DELETE CASCADE;
alter table public."medicines_ai_review" add constraint "medicines_ai_review_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."medicines_ai_review_source" add constraint "medicines_ai_review_source_review_id_fkey" FOREIGN KEY (review_id) REFERENCES medicines_ai_review(id) ON DELETE CASCADE;
alter table public."medicines_ai_review_source" add constraint "medicines_ai_review_source_source_file_id_fkey" FOREIGN KEY (source_file_id) REFERENCES medicines_ai_source_file(id) ON DELETE RESTRICT;
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_prescription_id_fkey" FOREIGN KEY (prescription_id) REFERENCES prescription(id) ON DELETE CASCADE;
alter table public."medicines_ai_source_file" add constraint "medicines_ai_source_file_reconciliation_session_id_fkey" FOREIGN KEY (reconciliation_session_id) REFERENCES medication_reconciliation_session(id) ON DELETE CASCADE;
alter table public."patient_allergy" add constraint "patient_allergy_ingredient_id_fkey" FOREIGN KEY (ingredient_id) REFERENCES medicine_reference_ingredient(id) ON DELETE SET NULL;
alter table public."patient_allergy" add constraint "patient_allergy_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE CASCADE;
alter table public."patient_allergy" add constraint "patient_allergy_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."patient_allergy" add constraint "patient_allergy_recorded_by_fkey" FOREIGN KEY (recorded_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."patient_medication" add constraint "patient_medication_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."patient_medication" add constraint "patient_medication_ingredient_id_fkey" FOREIGN KEY (ingredient_id) REFERENCES medicine_reference_ingredient(id) ON DELETE SET NULL;
alter table public."patient_medication" add constraint "patient_medication_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE CASCADE;
alter table public."patient_medication" add constraint "patient_medication_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."patient_medication" add constraint "patient_medication_product_id_fkey" FOREIGN KEY (product_id) REFERENCES medicine_reference_product(id) ON DELETE SET NULL;
alter table public."patient_medication" add constraint "patient_medication_reconciled_by_fkey" FOREIGN KEY (reconciled_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."prescription" add constraint "prescription_connection_id_fkey" FOREIGN KEY (connection_id) REFERENCES practice_integration_connection(id) ON DELETE SET NULL;
alter table public."prescription" add constraint "prescription_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."prescription" add constraint "prescription_encounter_id_fkey" FOREIGN KEY (encounter_id) REFERENCES practice_encounter(id) ON DELETE SET NULL;
alter table public."prescription" add constraint "prescription_interface_id_fkey" FOREIGN KEY (interface_id) REFERENCES integration_interface(id) ON DELETE SET NULL;
alter table public."prescription" add constraint "prescription_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."prescription" add constraint "prescription_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."prescription" add constraint "prescription_prescriber_user_id_fkey" FOREIGN KEY (prescriber_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."prescription" add constraint "prescription_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES integration_provider(id) ON DELETE SET NULL;
alter table public."prescription_item" add constraint "prescription_item_ingredient_id_fkey" FOREIGN KEY (ingredient_id) REFERENCES medicine_reference_ingredient(id) ON DELETE SET NULL;
alter table public."prescription_item" add constraint "prescription_item_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."prescription_item" add constraint "prescription_item_prescription_id_fkey" FOREIGN KEY (prescription_id) REFERENCES prescription(id) ON DELETE CASCADE;
alter table public."prescription_item" add constraint "prescription_item_product_id_fkey" FOREIGN KEY (product_id) REFERENCES medicine_reference_product(id) ON DELETE SET NULL;
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_assessed_by_fkey" FOREIGN KEY (assessed_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."prescription_safety_assessment" add constraint "prescription_safety_assessment_prescription_id_fkey" FOREIGN KEY (prescription_id) REFERENCES prescription(id) ON DELETE CASCADE;
alter table public."prescription_safety_finding" add constraint "prescription_safety_finding_assessment_id_fkey" FOREIGN KEY (assessment_id) REFERENCES prescription_safety_assessment(id) ON DELETE CASCADE;
alter table public."prescription_safety_finding" add constraint "prescription_safety_finding_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."prescription_safety_finding" add constraint "prescription_safety_finding_prescription_item_id_fkey" FOREIGN KEY (prescription_item_id) REFERENCES prescription_item(id) ON DELETE CASCADE;
alter table public."prescription_safety_finding" add constraint "prescription_safety_finding_source_rule_id_fkey" FOREIGN KEY (source_rule_id) REFERENCES medicine_interaction_rule(id) ON DELETE SET NULL;
alter table public."prescription_transmission_event" add constraint "prescription_transmission_event_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."prescription_transmission_event" add constraint "prescription_transmission_event_transmission_request_id_fkey" FOREIGN KEY (transmission_request_id) REFERENCES prescription_transmission_request(id) ON DELETE CASCADE;
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_connection_id_fkey" FOREIGN KEY (connection_id) REFERENCES practice_integration_connection(id) ON DELETE RESTRICT;
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_interface_id_fkey" FOREIGN KEY (interface_id) REFERENCES integration_interface(id) ON DELETE RESTRICT;
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_prescription_id_fkey" FOREIGN KEY (prescription_id) REFERENCES prescription(id) ON DELETE CASCADE;
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES integration_provider(id) ON DELETE RESTRICT;
alter table public."prescription_transmission_request" add constraint "prescription_transmission_request_queued_by_fkey" FOREIGN KEY (queued_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS med_recon_item_practice_fk_idx ON public.medication_reconciliation_item USING btree (practice_id);
CREATE INDEX IF NOT EXISTS med_recon_item_session_idx ON public.medication_reconciliation_item USING btree (session_id, review_status);
CREATE INDEX IF NOT EXISTS med_recon_item_existing_idx ON public.medication_reconciliation_item USING btree (existing_medication_id) WHERE (existing_medication_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS med_recon_item_product_idx ON public.medication_reconciliation_item USING btree (product_id) WHERE (product_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS med_recon_item_ingredient_idx ON public.medication_reconciliation_item USING btree (ingredient_id) WHERE (ingredient_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS med_recon_item_reviewed_by_idx ON public.medication_reconciliation_item USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS med_recon_practice_patient_idx ON public.medication_reconciliation_session USING btree (practice_id, patient_id, status);
CREATE INDEX IF NOT EXISTS med_recon_session_patient_fk_idx ON public.medication_reconciliation_session USING btree (patient_id);
CREATE INDEX IF NOT EXISTS med_recon_encounter_idx ON public.medication_reconciliation_session USING btree (encounter_id) WHERE (encounter_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS med_recon_started_by_idx ON public.medication_reconciliation_session USING btree (started_by);
CREATE INDEX IF NOT EXISTS med_recon_completed_by_idx ON public.medication_reconciliation_session USING btree (completed_by) WHERE (completed_by IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS medicine_interaction_pair_release_uq ON public.medicine_interaction_rule USING btree (source_release_id, LEAST(ingredient_a_id, ingredient_b_id), GREATEST(ingredient_a_id, ingredient_b_id), title);
CREATE INDEX IF NOT EXISTS medicine_interaction_a_idx ON public.medicine_interaction_rule USING btree (ingredient_a_id) WHERE active;
CREATE INDEX IF NOT EXISTS medicine_interaction_b_idx ON public.medicine_interaction_rule USING btree (ingredient_b_id) WHERE active;
CREATE INDEX IF NOT EXISTS medicine_product_ingredient_ing_idx ON public.medicine_product_ingredient USING btree (ingredient_id);
CREATE INDEX IF NOT EXISTS medicine_reference_ingredient_release_idx ON public.medicine_reference_ingredient USING btree (source_release_id) WHERE (source_release_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS medicine_product_nappi_release_uq ON public.medicine_reference_product USING btree (source_release_id, nappi_code) WHERE (nappi_code IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS medicine_product_sahpra_release_uq ON public.medicine_reference_product USING btree (source_release_id, sahpra_registration_no) WHERE (sahpra_registration_no IS NOT NULL);
CREATE INDEX IF NOT EXISTS medicine_product_name_idx ON public.medicine_reference_product USING btree (lower(product_name));
CREATE INDEX IF NOT EXISTS medicine_product_source_idx ON public.medicine_reference_product USING btree (source_release_id);
CREATE INDEX IF NOT EXISTS medicines_ai_review_practice_idx ON public.medicines_ai_review USING btree (practice_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS medicines_ai_review_patient_idx ON public.medicines_ai_review USING btree (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS medicines_ai_review_prescription_idx ON public.medicines_ai_review USING btree (prescription_id) WHERE (prescription_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS medicines_ai_review_recon_idx ON public.medicines_ai_review USING btree (reconciliation_session_id) WHERE (reconciliation_session_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS medicines_ai_review_provider_idx ON public.medicines_ai_review USING btree (provider_config_id);
CREATE INDEX IF NOT EXISTS medicines_ai_review_created_by_idx ON public.medicines_ai_review USING btree (created_by);
CREATE INDEX IF NOT EXISTS medicines_ai_review_reviewed_by_idx ON public.medicines_ai_review USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS medicines_ai_review_applied_by_idx ON public.medicines_ai_review USING btree (applied_by) WHERE (applied_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS medicines_ai_review_capability_idx ON public.medicines_ai_review USING btree (capability_key);
CREATE INDEX IF NOT EXISTS medicines_ai_review_source_file_idx ON public.medicines_ai_review_source USING btree (source_file_id);
CREATE INDEX IF NOT EXISTS medicines_ai_source_practice_idx ON public.medicines_ai_source_file USING btree (practice_id, created_at DESC);
CREATE INDEX IF NOT EXISTS medicines_ai_source_patient_idx ON public.medicines_ai_source_file USING btree (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS medicines_ai_source_recon_idx ON public.medicines_ai_source_file USING btree (reconciliation_session_id) WHERE (reconciliation_session_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS medicines_ai_source_rx_idx ON public.medicines_ai_source_file USING btree (prescription_id) WHERE (prescription_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS medicines_ai_source_created_by_idx ON public.medicines_ai_source_file USING btree (created_by);
CREATE INDEX IF NOT EXISTS patient_allergy_practice_patient_idx ON public.patient_allergy USING btree (practice_id, patient_id, status);
CREATE INDEX IF NOT EXISTS patient_allergy_ingredient_idx ON public.patient_allergy USING btree (ingredient_id) WHERE (ingredient_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS patient_allergy_recorded_by_idx ON public.patient_allergy USING btree (recorded_by) WHERE (recorded_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS patient_allergy_patient_fk_idx ON public.patient_allergy USING btree (patient_id);
CREATE INDEX IF NOT EXISTS patient_medication_practice_patient_idx ON public.patient_medication USING btree (practice_id, patient_id, status);
CREATE INDEX IF NOT EXISTS patient_medication_product_idx ON public.patient_medication USING btree (product_id) WHERE (product_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS patient_medication_ingredient_idx ON public.patient_medication USING btree (ingredient_id) WHERE (ingredient_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS patient_medication_reconciled_by_idx ON public.patient_medication USING btree (reconciled_by) WHERE (reconciled_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS patient_medication_created_by_idx ON public.patient_medication USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS patient_medication_patient_fk_idx ON public.patient_medication USING btree (patient_id);
CREATE INDEX IF NOT EXISTS prescription_practice_patient_idx ON public.prescription USING btree (practice_id, patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS prescription_encounter_idx ON public.prescription USING btree (encounter_id) WHERE (encounter_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_status_idx ON public.prescription USING btree (practice_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS prescription_provider_idx ON public.prescription USING btree (provider_id) WHERE (provider_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_interface_idx ON public.prescription USING btree (interface_id) WHERE (interface_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_connection_idx ON public.prescription USING btree (connection_id) WHERE (connection_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_prescriber_idx ON public.prescription USING btree (prescriber_user_id);
CREATE INDEX IF NOT EXISTS prescription_created_by_idx ON public.prescription USING btree (created_by);
CREATE INDEX IF NOT EXISTS prescription_patient_fk_idx ON public.prescription USING btree (patient_id);
CREATE INDEX IF NOT EXISTS prescription_item_rx_idx ON public.prescription_item USING btree (prescription_id);
CREATE INDEX IF NOT EXISTS prescription_item_product_idx ON public.prescription_item USING btree (product_id) WHERE (product_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_item_ingredient_idx ON public.prescription_item USING btree (ingredient_id) WHERE (ingredient_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_item_practice_fk_idx ON public.prescription_item USING btree (practice_id);
CREATE INDEX IF NOT EXISTS prescription_safety_practice_idx ON public.prescription_safety_assessment USING btree (practice_id, assessed_at DESC);
CREATE INDEX IF NOT EXISTS prescription_safety_assessed_by_idx ON public.prescription_safety_assessment USING btree (assessed_by);
CREATE INDEX IF NOT EXISTS prescription_finding_assessment_idx ON public.prescription_safety_finding USING btree (assessment_id, severity);
CREATE INDEX IF NOT EXISTS prescription_finding_item_idx ON public.prescription_safety_finding USING btree (prescription_item_id) WHERE (prescription_item_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_finding_rule_idx ON public.prescription_safety_finding USING btree (source_rule_id) WHERE (source_rule_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS prescription_safety_finding_practice_fk_idx ON public.prescription_safety_finding USING btree (practice_id);
CREATE INDEX IF NOT EXISTS prescription_tx_event_request_idx ON public.prescription_transmission_event USING btree (transmission_request_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS prescription_tx_event_practice_idx ON public.prescription_transmission_event USING btree (practice_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS prescription_tx_practice_status_idx ON public.prescription_transmission_request USING btree (practice_id, status, queued_at DESC);
CREATE INDEX IF NOT EXISTS prescription_tx_provider_idx ON public.prescription_transmission_request USING btree (provider_id);
CREATE INDEX IF NOT EXISTS prescription_tx_interface_idx ON public.prescription_transmission_request USING btree (interface_id);
CREATE INDEX IF NOT EXISTS prescription_tx_connection_idx ON public.prescription_transmission_request USING btree (connection_id);
CREATE INDEX IF NOT EXISTS prescription_tx_queued_by_idx ON public.prescription_transmission_request USING btree (queued_by);

alter table public."medication_reconciliation_item" enable row level security;
revoke all on public."medication_reconciliation_item" from anon, authenticated;
grant insert, select, update on public."medication_reconciliation_item" to authenticated;
create policy "med_recon_item_insert" on public."medication_reconciliation_item" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "med_recon_item_read" on public."medication_reconciliation_item" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "med_recon_item_update" on public."medication_reconciliation_item" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."medication_reconciliation_session" enable row level security;
revoke all on public."medication_reconciliation_session" from anon, authenticated;
grant insert, select, update on public."medication_reconciliation_session" to authenticated;
create policy "med_recon_session_insert" on public."medication_reconciliation_session" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (started_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_session.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "med_recon_session_read" on public."medication_reconciliation_session" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_session.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "med_recon_session_update" on public."medication_reconciliation_session" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_session.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medication_reconciliation_session.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."medicine_interaction_rule" enable row level security;
revoke all on public."medicine_interaction_rule" from anon, authenticated;
grant select on public."medicine_interaction_rule" to authenticated;
create policy "medicine_interaction_rule_read" on public."medicine_interaction_rule" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND m.active))));
alter table public."medicine_product_ingredient" enable row level security;
revoke all on public."medicine_product_ingredient" from anon, authenticated;
grant select on public."medicine_product_ingredient" to authenticated;
create policy "medicine_product_ingredient_read" on public."medicine_product_ingredient" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND m.active))));
alter table public."medicine_reference_ingredient" enable row level security;
revoke all on public."medicine_reference_ingredient" from anon, authenticated;
grant select on public."medicine_reference_ingredient" to authenticated;
create policy "medicine_reference_ingredient_read" on public."medicine_reference_ingredient" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND m.active))));
alter table public."medicine_reference_product" enable row level security;
revoke all on public."medicine_reference_product" from anon, authenticated;
grant select on public."medicine_reference_product" to authenticated;
create policy "medicine_reference_product_read" on public."medicine_reference_product" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND m.active))));
alter table public."medicines_ai_review" enable row level security;
revoke all on public."medicines_ai_review" from anon, authenticated;
grant select on public."medicines_ai_review" to authenticated;
create policy "medicines_ai_review_decide" on public."medicines_ai_review" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (status = 'completed'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medicines_ai_review.practice_id) AND m.active AND (m.role = 'practitioner'::practice_staff_role)))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (status = ANY (ARRAY['clinician_accepted'::text, 'discarded'::text])) AND (reviewed_by = ( SELECT auth.uid() AS uid)) AND (reviewed_at IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medicines_ai_review.practice_id) AND m.active AND (m.role = 'practitioner'::practice_staff_role))))));
create policy "medicines_ai_review_read" on public."medicines_ai_review" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medicines_ai_review.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."medicines_ai_review_source" enable row level security;
revoke all on public."medicines_ai_review_source" from anon, authenticated;
grant select on public."medicines_ai_review_source" to authenticated;
create policy "medicines_ai_review_source_read" on public."medicines_ai_review_source" for select to authenticated using ((EXISTS ( SELECT 1
   FROM (medicines_ai_review r
     JOIN practice_staff_member m ON ((m.practice_id = r.practice_id)))
  WHERE ((r.id = medicines_ai_review_source.review_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."medicines_ai_source_file" enable row level security;
revoke all on public."medicines_ai_source_file" from anon, authenticated;
grant insert, select, delete on public."medicines_ai_source_file" to authenticated;
create policy "medicines_ai_source_delete" on public."medicines_ai_source_file" for delete to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medicines_ai_source_file.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "medicines_ai_source_insert" on public."medicines_ai_source_file" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medicines_ai_source_file.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "medicines_ai_source_read" on public."medicines_ai_source_file" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = medicines_ai_source_file.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."patient_allergy" enable row level security;
revoke all on public."patient_allergy" from anon, authenticated;
grant insert, select, update on public."patient_allergy" to authenticated;
create policy "patient_allergy_insert" on public."patient_allergy" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_allergy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))) AND ((recorded_by IS NULL) OR (recorded_by = ( SELECT auth.uid() AS uid)))));
create policy "patient_allergy_read" on public."patient_allergy" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_allergy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "patient_allergy_update" on public."patient_allergy" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_allergy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_allergy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."patient_medication" enable row level security;
revoke all on public."patient_medication" from anon, authenticated;
grant insert, select, update on public."patient_medication" to authenticated;
create policy "patient_medication_insert" on public."patient_medication" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_medication.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))) AND ((created_by IS NULL) OR (created_by = ( SELECT auth.uid() AS uid)))));
create policy "patient_medication_read" on public."patient_medication" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_medication.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "patient_medication_update" on public."patient_medication" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_medication.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = patient_medication.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."prescription" enable row level security;
revoke all on public."prescription" from anon, authenticated;
grant insert, select, update on public."prescription" to authenticated;
create policy "prescription_insert" on public."prescription" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (prescriber_user_id = ( SELECT auth.uid() AS uid)) AND (created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription.practice_id) AND m.active AND (m.role = 'practitioner'::practice_staff_role))))));
create policy "prescription_read" on public."prescription" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "prescription_update" on public."prescription" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (prescriber_user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription.practice_id) AND m.active AND (m.role = 'practitioner'::practice_staff_role)))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (prescriber_user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription.practice_id) AND m.active AND (m.role = 'practitioner'::practice_staff_role))))));
alter table public."prescription_item" enable row level security;
revoke all on public."prescription_item" from anon, authenticated;
grant insert, select, update on public."prescription_item" to authenticated;
create policy "prescription_item_insert" on public."prescription_item" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM (prescription p
     JOIN practice_staff_member m ON ((m.practice_id = p.practice_id)))
  WHERE ((p.id = prescription_item.prescription_id) AND (p.practice_id = prescription_item.practice_id) AND (p.prescriber_user_id = ( SELECT auth.uid() AS uid)) AND (p.status = ANY (ARRAY['draft'::text, 'safety_review'::text, 'blocked'::text])) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.active AND (m.role = 'practitioner'::practice_staff_role))))));
create policy "prescription_item_read" on public."prescription_item" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "prescription_item_update" on public."prescription_item" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM (prescription p
     JOIN practice_staff_member m ON ((m.practice_id = p.practice_id)))
  WHERE ((p.id = prescription_item.prescription_id) AND (p.practice_id = prescription_item.practice_id) AND (p.prescriber_user_id = ( SELECT auth.uid() AS uid)) AND (p.status = ANY (ARRAY['draft'::text, 'safety_review'::text, 'blocked'::text])) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.active AND (m.role = 'practitioner'::practice_staff_role)))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM (prescription p
     JOIN practice_staff_member m ON ((m.practice_id = p.practice_id)))
  WHERE ((p.id = prescription_item.prescription_id) AND (p.practice_id = prescription_item.practice_id) AND (p.prescriber_user_id = ( SELECT auth.uid() AS uid)) AND (p.status = ANY (ARRAY['draft'::text, 'safety_review'::text, 'blocked'::text])) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.active AND (m.role = 'practitioner'::practice_staff_role))))));
alter table public."prescription_safety_assessment" enable row level security;
revoke all on public."prescription_safety_assessment" from anon, authenticated;
grant select on public."prescription_safety_assessment" to authenticated;
create policy "prescription_safety_read" on public."prescription_safety_assessment" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription_safety_assessment.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."prescription_safety_finding" enable row level security;
revoke all on public."prescription_safety_finding" from anon, authenticated;
grant select on public."prescription_safety_finding" to authenticated;
create policy "prescription_finding_read" on public."prescription_safety_finding" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription_safety_finding.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."prescription_transmission_event" enable row level security;
revoke all on public."prescription_transmission_event" from anon, authenticated;
grant select on public."prescription_transmission_event" to authenticated;
create policy "prescription_tx_event_read" on public."prescription_transmission_event" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription_transmission_event.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."prescription_transmission_request" enable row level security;
revoke all on public."prescription_transmission_request" from anon, authenticated;
grant select on public."prescription_transmission_request" to authenticated;
create policy "prescription_tx_read" on public."prescription_transmission_request" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = prescription_transmission_request.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
commit;
