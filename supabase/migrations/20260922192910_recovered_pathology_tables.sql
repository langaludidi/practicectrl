-- Recovered pathology schema from the connected project's catalog.
-- Historical validator migrations omitted the original table DDL. No patient data is copied.
begin;

create table public."pathology_ai_review" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "result_id" uuid not null,
  "provider_config_id" uuid not null,
  "capability_key" text default 'pathology.result_intelligence'::text not null,
  "status" text default 'requested'::text not null,
  "input_mode" text default 'structured'::text not null,
  "source_document_count" integer default 0 not null,
  "input_sha256" text not null,
  "model_id" text not null,
  "summary" text,
  "key_findings" jsonb default '[]'::jsonb not null,
  "abnormal_findings" jsonb default '[]'::jsonb not null,
  "critical_findings" jsonb default '[]'::jsonb not null,
  "extracted_observations" jsonb default '[]'::jsonb not null,
  "clinician_attention" jsonb default '[]'::jsonb not null,
  "limitations" jsonb default '[]'::jsonb not null,
  "confidence" text,
  "provider_output_sha256" text,
  "error_code" text,
  "error_detail" text,
  "created_by" uuid not null,
  "created_at" timestamp with time zone default now() not null,
  "completed_at" timestamp with time zone,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone
);

create table public."pathology_ai_review_source" (
  "review_id" uuid not null,
  "document_id" uuid not null,
  "content_type" text,
  "sha256" text,
  "source_index" integer not null
);

create table public."pathology_audit_event" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid,
  "entity_type" text not null,
  "entity_id" uuid not null,
  "event_type" text not null,
  "actor_user_id" uuid,
  "metadata" jsonb default '{}'::jsonb not null,
  "occurred_at" timestamp with time zone default now() not null
);

create table public."pathology_follow_up_action" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "result_id" uuid not null,
  "action_type" text not null,
  "status" text default 'planned'::text not null,
  "due_at" timestamp with time zone,
  "details" text,
  "appointment_request_id" uuid,
  "created_by" uuid,
  "completed_by" uuid,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."pathology_order" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "encounter_id" uuid,
  "provider_id" uuid not null,
  "interface_id" uuid,
  "connection_id" uuid,
  "order_number" text not null,
  "status" text default 'draft'::text not null,
  "delivery_mode" text default 'manual'::text not null,
  "transport_status" text default 'not_sent'::text not null,
  "priority" text default 'routine'::text not null,
  "clinical_indication" text,
  "fasting_required" boolean,
  "patient_instructions" text,
  "external_order_ref" text,
  "ordered_by" uuid,
  "ordered_at" timestamp with time zone,
  "submitted_at" timestamp with time zone,
  "collected_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "cancelled_at" timestamp with time zone,
  "cancellation_reason" text,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "order_category" text default 'routine_lab'::text not null,
  "treating_practitioner_user_id" uuid
);

create table public."pathology_order_item" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "order_id" uuid not null,
  "test_code" text,
  "test_name" text not null,
  "specimen_type" text,
  "instructions" text,
  "status" text default 'requested'::text not null,
  "external_test_ref" text,
  "created_at" timestamp with time zone default now() not null,
  "concept_id" uuid
);

create table public."pathology_provider_test_mapping" (
  "id" uuid default gen_random_uuid() not null,
  "provider_id" uuid not null,
  "concept_id" uuid not null,
  "provider_test_code" text,
  "provider_test_name" text not null,
  "specimen_type" text,
  "mapping_status" text default 'proposed'::text not null,
  "source_reference" text,
  "effective_from" date,
  "effective_to" date,
  "verified_by" uuid,
  "verified_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."pathology_release_policy" (
  "practice_id" uuid not null,
  "default_mode" text default 'after_clinician_review'::text not null,
  "minimum_delay_minutes" integer default 0 not null,
  "hold_critical" boolean default true not null,
  "hold_corrected_until_review" boolean default true not null,
  "updated_by" uuid,
  "updated_at" timestamp with time zone default now() not null
);

create table public."pathology_result" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "order_id" uuid not null,
  "patient_id" uuid not null,
  "encounter_id" uuid,
  "provider_id" uuid not null,
  "status" text default 'preliminary'::text not null,
  "overall_flag" text default 'unknown'::text not null,
  "external_result_ref" text,
  "accession_number" text,
  "specimen_collected_at" timestamp with time zone,
  "received_at" timestamp with time zone default now() not null,
  "reported_at" timestamp with time zone,
  "source_mode" text default 'manual'::text not null,
  "payload_sha256" text,
  "report_comment" text,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "version_no" integer default 1 not null,
  "correction_of_result_id" uuid,
  "correction_reason" text,
  "is_current" boolean default true not null,
  "superseded_at" timestamp with time zone,
  "superseded_by_result_id" uuid
);

create table public."pathology_result_acknowledgement" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "result_id" uuid not null,
  "acknowledgement_status" text default 'acknowledged'::text not null,
  "follow_up_plan" text,
  "patient_contacted_at" timestamp with time zone,
  "acknowledged_by" uuid not null,
  "acknowledged_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."pathology_result_document" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "result_id" uuid not null,
  "storage_path" text not null,
  "original_filename" text,
  "content_type" text,
  "sha256" text,
  "source_mode" text default 'manual'::text not null,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null
);

create table public."pathology_result_inbox" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "provider_id" uuid not null,
  "interface_id" uuid,
  "patient_id" uuid,
  "matched_order_id" uuid,
  "external_patient_ref" text,
  "external_order_ref" text,
  "external_result_ref" text,
  "accession_number" text,
  "source_mode" text default 'manual'::text not null,
  "status" text default 'unmatched'::text not null,
  "overall_flag_hint" text default 'unknown'::text not null,
  "payload_sha256" text,
  "payload_storage_path" text,
  "summary" text,
  "received_at" timestamp with time zone default now() not null,
  "matched_by" uuid,
  "matched_at" timestamp with time zone,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "match_confidence" integer,
  "match_basis" text,
  "resolution_note" text
);

create table public."pathology_result_item" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "result_id" uuid not null,
  "order_item_id" uuid,
  "test_code" text,
  "test_name" text not null,
  "value_type" text default 'text'::text not null,
  "value_numeric" numeric,
  "value_text" text,
  "unit" text,
  "reference_range" text,
  "flag" text default 'unknown'::text not null,
  "observation_at" timestamp with time zone,
  "comment" text,
  "created_at" timestamp with time zone default now() not null,
  "concept_id" uuid
);

create table public."pathology_result_release" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "result_id" uuid not null,
  "status" text default 'held'::text not null,
  "hold_reason" text,
  "release_after" timestamp with time zone,
  "approved_by" uuid,
  "approved_at" timestamp with time zone,
  "released_at" timestamp with time zone,
  "revoked_by" uuid,
  "revoked_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."pathology_safety_case" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "patient_id" uuid not null,
  "result_id" uuid not null,
  "severity" text not null,
  "status" text default 'open'::text not null,
  "assigned_user_id" uuid,
  "sla_due_at" timestamp with time zone not null,
  "escalation_level" integer default 0 not null,
  "last_escalated_at" timestamp with time zone,
  "acknowledged_at" timestamp with time zone,
  "resolved_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."pathology_safety_event" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "safety_case_id" uuid not null,
  "event_type" text not null,
  "escalation_level" integer,
  "detail" text,
  "actor_user_id" uuid,
  "occurred_at" timestamp with time zone default now() not null
);

create table public."pathology_specimen" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "order_id" uuid not null,
  "patient_id" uuid not null,
  "specimen_identifier" text,
  "specimen_type" text not null,
  "body_site" text,
  "status" text default 'ordered'::text not null,
  "collected_at" timestamp with time zone,
  "received_by_lab_at" timestamp with time zone,
  "rejection_reason" text,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."pathology_specimen_event" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "specimen_id" uuid not null,
  "from_status" text,
  "to_status" text not null,
  "note" text,
  "actor_user_id" uuid,
  "occurred_at" timestamp with time zone default now() not null
);

create table public."pathology_test_concept" (
  "id" uuid default gen_random_uuid() not null,
  "canonical_key" text not null,
  "display_name" text not null,
  "category" text default 'laboratory'::text not null,
  "specimen_type" text,
  "loinc_code" text,
  "loinc_version" text,
  "active" boolean default true not null,
  "created_by" uuid,
  "verified_by" uuid,
  "verified_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

alter table public."pathology_ai_review" add constraint "pathology_ai_review_check" CHECK ((((status = ANY (ARRAY['completed'::text, 'clinician_accepted'::text, 'discarded'::text, 'failed'::text])) AND (completed_at IS NOT NULL)) OR (status = ANY (ARRAY['requested'::text, 'processing'::text]))));
alter table public."pathology_ai_review" add constraint "pathology_ai_review_check1" CHECK (((status <> 'clinician_accepted'::text) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))));
alter table public."pathology_ai_review" add constraint "pathology_ai_review_confidence_check" CHECK (((confidence IS NULL) OR (confidence = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text]))));
alter table public."pathology_ai_review" add constraint "pathology_ai_review_input_mode_check" CHECK ((input_mode = ANY (ARRAY['structured'::text, 'document'::text, 'mixed'::text])));
alter table public."pathology_ai_review" add constraint "pathology_ai_review_input_sha256_check" CHECK ((input_sha256 ~ '^[a-f0-9]{64}$'::text));
alter table public."pathology_ai_review" add constraint "pathology_ai_review_pkey" PRIMARY KEY (id);
alter table public."pathology_ai_review" add constraint "pathology_ai_review_provider_output_sha256_check" CHECK (((provider_output_sha256 IS NULL) OR (provider_output_sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."pathology_ai_review" add constraint "pathology_ai_review_source_document_count_check" CHECK (((source_document_count >= 0) AND (source_document_count <= 10)));
alter table public."pathology_ai_review" add constraint "pathology_ai_review_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'processing'::text, 'completed'::text, 'failed'::text, 'clinician_accepted'::text, 'discarded'::text])));
alter table public."pathology_ai_review_source" add constraint "pathology_ai_review_source_pkey" PRIMARY KEY (review_id, document_id);
alter table public."pathology_ai_review_source" add constraint "pathology_ai_review_source_review_id_source_index_key" UNIQUE (review_id, source_index);
alter table public."pathology_ai_review_source" add constraint "pathology_ai_review_source_sha256_check" CHECK (((sha256 IS NULL) OR (sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."pathology_ai_review_source" add constraint "pathology_ai_review_source_source_index_check" CHECK (((source_index >= 1) AND (source_index <= 10)));
alter table public."pathology_audit_event" add constraint "pathology_audit_event_entity_type_check" CHECK ((entity_type = ANY (ARRAY['order'::text, 'result'::text, 'document'::text])));
alter table public."pathology_audit_event" add constraint "pathology_audit_event_pkey" PRIMARY KEY (id);
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_action_type_check" CHECK ((action_type = ANY (ARRAY['patient_contact'::text, 'repeat_pathology'::text, 'consultation'::text, 'referral'::text, 'medication_review'::text, 'other'::text])));
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_pkey" PRIMARY KEY (id);
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_status_check" CHECK ((status = ANY (ARRAY['planned'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])));
alter table public."pathology_order" add constraint "pathology_order_category_check" CHECK ((order_category = ANY (ARRAY['routine_lab'::text, 'microbiology'::text, 'molecular'::text, 'cytology'::text, 'histology'::text, 'biopsy'::text, 'genetic'::text, 'other'::text])));
alter table public."pathology_order" add constraint "pathology_order_delivery_mode_check" CHECK ((delivery_mode = ANY (ARRAY['manual'::text, 'electronic'::text])));
alter table public."pathology_order" add constraint "pathology_order_pkey" PRIMARY KEY (id);
alter table public."pathology_order" add constraint "pathology_order_practice_id_order_number_key" UNIQUE (practice_id, order_number);
alter table public."pathology_order" add constraint "pathology_order_priority_check" CHECK ((priority = ANY (ARRAY['routine'::text, 'urgent'::text, 'stat'::text])));
alter table public."pathology_order" add constraint "pathology_order_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'ordered'::text, 'submitted'::text, 'acknowledged'::text, 'collected'::text, 'in_progress'::text, 'partial'::text, 'completed'::text, 'cancelled'::text, 'failed'::text])));
alter table public."pathology_order" add constraint "pathology_order_transport_status_check" CHECK ((transport_status = ANY (ARRAY['not_sent'::text, 'manual'::text, 'queued'::text, 'submitted'::text, 'accepted'::text, 'rejected'::text, 'failed'::text])));
alter table public."pathology_order_item" add constraint "pathology_order_item_order_id_test_name_test_code_key" UNIQUE (order_id, test_name, test_code);
alter table public."pathology_order_item" add constraint "pathology_order_item_pkey" PRIMARY KEY (id);
alter table public."pathology_order_item" add constraint "pathology_order_item_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'cancelled'::text, 'collected'::text, 'in_progress'::text, 'resulted'::text])));
alter table public."pathology_provider_test_mapping" add constraint "pathology_provider_test_mapping_check" CHECK (((effective_to IS NULL) OR (effective_from IS NULL) OR (effective_to >= effective_from)));
alter table public."pathology_provider_test_mapping" add constraint "pathology_provider_test_mapping_mapping_status_check" CHECK ((mapping_status = ANY (ARRAY['proposed'::text, 'verified'::text, 'retired'::text])));
alter table public."pathology_provider_test_mapping" add constraint "pathology_provider_test_mapping_pkey" PRIMARY KEY (id);
alter table public."pathology_release_policy" add constraint "pathology_release_policy_default_mode_check" CHECK ((default_mode = ANY (ARRAY['after_clinician_review'::text, 'manual_only'::text, 'delayed_after_review'::text])));
alter table public."pathology_release_policy" add constraint "pathology_release_policy_minimum_delay_minutes_check" CHECK (((minimum_delay_minutes >= 0) AND (minimum_delay_minutes <= 10080)));
alter table public."pathology_release_policy" add constraint "pathology_release_policy_pkey" PRIMARY KEY (practice_id);
alter table public."pathology_result" add constraint "pathology_result_overall_flag_check" CHECK ((overall_flag = ANY (ARRAY['normal'::text, 'abnormal'::text, 'critical'::text, 'unknown'::text])));
alter table public."pathology_result" add constraint "pathology_result_payload_sha256_check" CHECK (((payload_sha256 IS NULL) OR (payload_sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."pathology_result" add constraint "pathology_result_pkey" PRIMARY KEY (id);
alter table public."pathology_result" add constraint "pathology_result_source_mode_check" CHECK ((source_mode = ANY (ARRAY['manual'::text, 'electronic'::text, 'sandbox'::text])));
alter table public."pathology_result" add constraint "pathology_result_status_check" CHECK ((status = ANY (ARRAY['preliminary'::text, 'final'::text, 'corrected'::text, 'cancelled'::text])));
alter table public."pathology_result" add constraint "pathology_result_version_no_check" CHECK ((version_no >= 1));
alter table public."pathology_result_acknowledgement" add constraint "pathology_result_acknowledgement_acknowledgement_status_check" CHECK ((acknowledgement_status = ANY (ARRAY['acknowledged'::text, 'action_required'::text, 'follow_up_arranged'::text, 'patient_contacted'::text])));
alter table public."pathology_result_acknowledgement" add constraint "pathology_result_acknowledgement_pkey" PRIMARY KEY (id);
alter table public."pathology_result_acknowledgement" add constraint "pathology_result_acknowledgement_result_id_key" UNIQUE (result_id);
alter table public."pathology_result_document" add constraint "pathology_result_document_pkey" PRIMARY KEY (id);
alter table public."pathology_result_document" add constraint "pathology_result_document_sha256_check" CHECK (((sha256 IS NULL) OR (sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."pathology_result_document" add constraint "pathology_result_document_source_mode_check" CHECK ((source_mode = ANY (ARRAY['manual'::text, 'electronic'::text, 'sandbox'::text])));
alter table public."pathology_result_document" add constraint "pathology_result_document_storage_path_key" UNIQUE (storage_path);
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_match_confidence_check" CHECK (((match_confidence >= 0) AND (match_confidence <= 100)));
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_overall_flag_hint_check" CHECK ((overall_flag_hint = ANY (ARRAY['normal'::text, 'abnormal'::text, 'critical'::text, 'unknown'::text])));
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_payload_sha256_check" CHECK (((payload_sha256 IS NULL) OR (payload_sha256 ~ '^[a-f0-9]{64}$'::text)));
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_pkey" PRIMARY KEY (id);
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_source_mode_check" CHECK ((source_mode = ANY (ARRAY['manual'::text, 'electronic'::text])));
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_status_check" CHECK ((status = ANY (ARRAY['unmatched'::text, 'patient_matched'::text, 'order_matched'::text, 'filed'::text, 'duplicate'::text, 'quarantined'::text, 'rejected'::text])));
alter table public."pathology_result_item" add constraint "pathology_result_item_check" CHECK ((((value_type = 'numeric'::text) AND (value_numeric IS NOT NULL)) OR ((value_type = ANY (ARRAY['text'::text, 'qualitative'::text])) AND (NULLIF(TRIM(BOTH FROM COALESCE(value_text, ''::text)), ''::text) IS NOT NULL))));
alter table public."pathology_result_item" add constraint "pathology_result_item_flag_check" CHECK ((flag = ANY (ARRAY['normal'::text, 'high'::text, 'low'::text, 'abnormal'::text, 'critical'::text, 'unknown'::text])));
alter table public."pathology_result_item" add constraint "pathology_result_item_pkey" PRIMARY KEY (id);
alter table public."pathology_result_item" add constraint "pathology_result_item_value_type_check" CHECK ((value_type = ANY (ARRAY['numeric'::text, 'text'::text, 'qualitative'::text])));
alter table public."pathology_result_release" add constraint "pathology_result_release_pkey" PRIMARY KEY (id);
alter table public."pathology_result_release" add constraint "pathology_result_release_result_id_key" UNIQUE (result_id);
alter table public."pathology_result_release" add constraint "pathology_result_release_status_check" CHECK ((status = ANY (ARRAY['held'::text, 'approved'::text, 'released'::text, 'revoked'::text])));
alter table public."pathology_safety_case" add constraint "pathology_safety_case_escalation_level_check" CHECK (((escalation_level >= 0) AND (escalation_level <= 5)));
alter table public."pathology_safety_case" add constraint "pathology_safety_case_pkey" PRIMARY KEY (id);
alter table public."pathology_safety_case" add constraint "pathology_safety_case_result_id_key" UNIQUE (result_id);
alter table public."pathology_safety_case" add constraint "pathology_safety_case_severity_check" CHECK ((severity = ANY (ARRAY['normal'::text, 'abnormal'::text, 'critical'::text, 'unknown'::text])));
alter table public."pathology_safety_case" add constraint "pathology_safety_case_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'cancelled'::text])));
alter table public."pathology_safety_event" add constraint "pathology_safety_event_event_type_check" CHECK ((event_type = ANY (ARRAY['opened'::text, 'escalated'::text, 'acknowledged'::text, 'resolved'::text, 'cancelled'::text])));
alter table public."pathology_safety_event" add constraint "pathology_safety_event_pkey" PRIMARY KEY (id);
alter table public."pathology_specimen" add constraint "pathology_specimen_pkey" PRIMARY KEY (id);
alter table public."pathology_specimen" add constraint "pathology_specimen_status_check" CHECK ((status = ANY (ARRAY['ordered'::text, 'collected'::text, 'received_by_lab'::text, 'processing'::text, 'completed'::text, 'rejected'::text, 'cancelled'::text])));
alter table public."pathology_specimen_event" add constraint "pathology_specimen_event_pkey" PRIMARY KEY (id);
alter table public."pathology_test_concept" add constraint "pathology_test_concept_canonical_key_check" CHECK ((canonical_key ~ '^[a-z0-9][a-z0-9._-]{1,119}$'::text));
alter table public."pathology_test_concept" add constraint "pathology_test_concept_canonical_key_key" UNIQUE (canonical_key);
alter table public."pathology_test_concept" add constraint "pathology_test_concept_pkey" PRIMARY KEY (id);

alter table public."pathology_ai_review" add constraint "pathology_ai_review_capability_key_fkey" FOREIGN KEY (capability_key) REFERENCES assist_capability(capability_key) ON DELETE RESTRICT;
alter table public."pathology_ai_review" add constraint "pathology_ai_review_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."pathology_ai_review" add constraint "pathology_ai_review_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."pathology_ai_review" add constraint "pathology_ai_review_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_ai_review" add constraint "pathology_ai_review_provider_config_id_fkey" FOREIGN KEY (provider_config_id) REFERENCES assist_provider_config(id) ON DELETE RESTRICT;
alter table public."pathology_ai_review" add constraint "pathology_ai_review_result_id_fkey" FOREIGN KEY (result_id) REFERENCES pathology_result(id) ON DELETE CASCADE;
alter table public."pathology_ai_review" add constraint "pathology_ai_review_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_ai_review_source" add constraint "pathology_ai_review_source_document_id_fkey" FOREIGN KEY (document_id) REFERENCES pathology_result_document(id) ON DELETE RESTRICT;
alter table public."pathology_ai_review_source" add constraint "pathology_ai_review_source_review_id_fkey" FOREIGN KEY (review_id) REFERENCES pathology_ai_review(id) ON DELETE CASCADE;
alter table public."pathology_audit_event" add constraint "pathology_audit_event_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_audit_event" add constraint "pathology_audit_event_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE SET NULL;
alter table public."pathology_audit_event" add constraint "pathology_audit_event_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_appointment_request_id_fkey" FOREIGN KEY (appointment_request_id) REFERENCES appointment_request(id) ON DELETE SET NULL;
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_completed_by_fkey" FOREIGN KEY (completed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_follow_up_action" add constraint "pathology_follow_up_action_result_id_fkey" FOREIGN KEY (result_id) REFERENCES pathology_result(id) ON DELETE CASCADE;
alter table public."pathology_order" add constraint "pathology_order_connection_id_fkey" FOREIGN KEY (connection_id) REFERENCES practice_integration_connection(id) ON DELETE SET NULL;
alter table public."pathology_order" add constraint "pathology_order_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_order" add constraint "pathology_order_encounter_id_fkey" FOREIGN KEY (encounter_id) REFERENCES practice_encounter(id) ON DELETE SET NULL;
alter table public."pathology_order" add constraint "pathology_order_interface_id_fkey" FOREIGN KEY (interface_id) REFERENCES integration_interface(id) ON DELETE RESTRICT;
alter table public."pathology_order" add constraint "pathology_order_ordered_by_fkey" FOREIGN KEY (ordered_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_order" add constraint "pathology_order_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."pathology_order" add constraint "pathology_order_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_order" add constraint "pathology_order_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES integration_provider(id) ON DELETE RESTRICT;
alter table public."pathology_order" add constraint "pathology_order_treating_practitioner_user_id_fkey" FOREIGN KEY (treating_practitioner_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_order_item" add constraint "pathology_order_item_concept_id_fkey" FOREIGN KEY (concept_id) REFERENCES pathology_test_concept(id) ON DELETE SET NULL;
alter table public."pathology_order_item" add constraint "pathology_order_item_order_id_fkey" FOREIGN KEY (order_id) REFERENCES pathology_order(id) ON DELETE CASCADE;
alter table public."pathology_order_item" add constraint "pathology_order_item_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_provider_test_mapping" add constraint "pathology_provider_test_mapping_concept_id_fkey" FOREIGN KEY (concept_id) REFERENCES pathology_test_concept(id) ON DELETE RESTRICT;
alter table public."pathology_provider_test_mapping" add constraint "pathology_provider_test_mapping_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES integration_provider(id) ON DELETE CASCADE;
alter table public."pathology_provider_test_mapping" add constraint "pathology_provider_test_mapping_verified_by_fkey" FOREIGN KEY (verified_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_release_policy" add constraint "pathology_release_policy_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_release_policy" add constraint "pathology_release_policy_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_result" add constraint "pathology_result_correction_of_result_id_fkey" FOREIGN KEY (correction_of_result_id) REFERENCES pathology_result(id) ON DELETE RESTRICT;
alter table public."pathology_result" add constraint "pathology_result_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_result" add constraint "pathology_result_encounter_id_fkey" FOREIGN KEY (encounter_id) REFERENCES practice_encounter(id) ON DELETE SET NULL;
alter table public."pathology_result" add constraint "pathology_result_order_id_fkey" FOREIGN KEY (order_id) REFERENCES pathology_order(id) ON DELETE RESTRICT;
alter table public."pathology_result" add constraint "pathology_result_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."pathology_result" add constraint "pathology_result_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_result" add constraint "pathology_result_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES integration_provider(id) ON DELETE RESTRICT;
alter table public."pathology_result" add constraint "pathology_result_superseded_by_result_id_fkey" FOREIGN KEY (superseded_by_result_id) REFERENCES pathology_result(id) ON DELETE RESTRICT;
alter table public."pathology_result_acknowledgement" add constraint "pathology_result_acknowledgement_acknowledged_by_fkey" FOREIGN KEY (acknowledged_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table public."pathology_result_acknowledgement" add constraint "pathology_result_acknowledgement_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_result_acknowledgement" add constraint "pathology_result_acknowledgement_result_id_fkey" FOREIGN KEY (result_id) REFERENCES pathology_result(id) ON DELETE CASCADE;
alter table public."pathology_result_document" add constraint "pathology_result_document_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_result_document" add constraint "pathology_result_document_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_result_document" add constraint "pathology_result_document_result_id_fkey" FOREIGN KEY (result_id) REFERENCES pathology_result(id) ON DELETE CASCADE;
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_interface_id_fkey" FOREIGN KEY (interface_id) REFERENCES integration_interface(id) ON DELETE SET NULL;
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_matched_by_fkey" FOREIGN KEY (matched_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_matched_order_id_fkey" FOREIGN KEY (matched_order_id) REFERENCES pathology_order(id) ON DELETE SET NULL;
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE SET NULL;
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_result_inbox" add constraint "pathology_result_inbox_provider_id_fkey" FOREIGN KEY (provider_id) REFERENCES integration_provider(id) ON DELETE RESTRICT;
alter table public."pathology_result_item" add constraint "pathology_result_item_concept_id_fkey" FOREIGN KEY (concept_id) REFERENCES pathology_test_concept(id) ON DELETE SET NULL;
alter table public."pathology_result_item" add constraint "pathology_result_item_order_item_id_fkey" FOREIGN KEY (order_item_id) REFERENCES pathology_order_item(id) ON DELETE SET NULL;
alter table public."pathology_result_item" add constraint "pathology_result_item_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_result_item" add constraint "pathology_result_item_result_id_fkey" FOREIGN KEY (result_id) REFERENCES pathology_result(id) ON DELETE CASCADE;
alter table public."pathology_result_release" add constraint "pathology_result_release_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_result_release" add constraint "pathology_result_release_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_result_release" add constraint "pathology_result_release_result_id_fkey" FOREIGN KEY (result_id) REFERENCES pathology_result(id) ON DELETE CASCADE;
alter table public."pathology_result_release" add constraint "pathology_result_release_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_safety_case" add constraint "pathology_safety_case_assigned_user_id_fkey" FOREIGN KEY (assigned_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_safety_case" add constraint "pathology_safety_case_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."pathology_safety_case" add constraint "pathology_safety_case_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_safety_case" add constraint "pathology_safety_case_result_id_fkey" FOREIGN KEY (result_id) REFERENCES pathology_result(id) ON DELETE CASCADE;
alter table public."pathology_safety_event" add constraint "pathology_safety_event_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_safety_event" add constraint "pathology_safety_event_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_safety_event" add constraint "pathology_safety_event_safety_case_id_fkey" FOREIGN KEY (safety_case_id) REFERENCES pathology_safety_case(id) ON DELETE CASCADE;
alter table public."pathology_specimen" add constraint "pathology_specimen_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_specimen" add constraint "pathology_specimen_order_id_fkey" FOREIGN KEY (order_id) REFERENCES pathology_order(id) ON DELETE CASCADE;
alter table public."pathology_specimen" add constraint "pathology_specimen_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE RESTRICT;
alter table public."pathology_specimen" add constraint "pathology_specimen_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_specimen_event" add constraint "pathology_specimen_event_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_specimen_event" add constraint "pathology_specimen_event_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."pathology_specimen_event" add constraint "pathology_specimen_event_specimen_id_fkey" FOREIGN KEY (specimen_id) REFERENCES pathology_specimen(id) ON DELETE CASCADE;
alter table public."pathology_test_concept" add constraint "pathology_test_concept_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."pathology_test_concept" add constraint "pathology_test_concept_verified_by_fkey" FOREIGN KEY (verified_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS pathology_ai_review_practice_status_idx ON public.pathology_ai_review USING btree (practice_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_ai_review_result_idx ON public.pathology_ai_review USING btree (result_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_ai_review_patient_idx ON public.pathology_ai_review USING btree (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_ai_review_provider_idx ON public.pathology_ai_review USING btree (provider_config_id);
CREATE INDEX IF NOT EXISTS pathology_ai_review_created_by_idx ON public.pathology_ai_review USING btree (created_by);
CREATE INDEX IF NOT EXISTS pathology_ai_review_reviewed_by_idx ON public.pathology_ai_review USING btree (reviewed_by) WHERE (reviewed_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_ai_review_capability_key_idx ON public.pathology_ai_review USING btree (capability_key);
CREATE INDEX IF NOT EXISTS pathology_ai_review_source_document_idx ON public.pathology_ai_review_source USING btree (document_id);
CREATE INDEX IF NOT EXISTS pathology_audit_practice_idx ON public.pathology_audit_event USING btree (practice_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS pathology_audit_patient_idx ON public.pathology_audit_event USING btree (patient_id, occurred_at DESC) WHERE (patient_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_audit_actor_idx ON public.pathology_audit_event USING btree (actor_user_id) WHERE (actor_user_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_follow_up_result_idx ON public.pathology_follow_up_action USING btree (result_id, created_at);
CREATE INDEX IF NOT EXISTS pathology_follow_up_patient_idx ON public.pathology_follow_up_action USING btree (patient_id, status, due_at);
CREATE INDEX IF NOT EXISTS pathology_follow_up_appointment_idx ON public.pathology_follow_up_action USING btree (appointment_request_id) WHERE (appointment_request_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_follow_up_created_by_idx ON public.pathology_follow_up_action USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_follow_up_completed_by_idx ON public.pathology_follow_up_action USING btree (completed_by) WHERE (completed_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_follow_up_practice_idx ON public.pathology_follow_up_action USING btree (practice_id, status, due_at);
CREATE INDEX IF NOT EXISTS pathology_order_practice_status_idx ON public.pathology_order USING btree (practice_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_order_patient_idx ON public.pathology_order USING btree (practice_id, patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_order_encounter_idx ON public.pathology_order USING btree (encounter_id) WHERE (encounter_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_order_provider_idx ON public.pathology_order USING btree (provider_id, status);
CREATE INDEX IF NOT EXISTS pathology_order_interface_idx ON public.pathology_order USING btree (interface_id) WHERE (interface_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_order_connection_idx ON public.pathology_order USING btree (connection_id) WHERE (connection_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_order_ordered_by_idx ON public.pathology_order USING btree (ordered_by) WHERE (ordered_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_order_created_by_idx ON public.pathology_order USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_order_patient_fk_idx ON public.pathology_order USING btree (patient_id);
CREATE INDEX IF NOT EXISTS pathology_order_treating_practitioner_idx ON public.pathology_order USING btree (practice_id, treating_practitioner_user_id, created_at DESC) WHERE (treating_practitioner_user_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_order_treating_practitioner_fk_idx ON public.pathology_order USING btree (treating_practitioner_user_id) WHERE (treating_practitioner_user_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_order_item_practice_idx ON public.pathology_order_item USING btree (practice_id, order_id);
CREATE INDEX IF NOT EXISTS pathology_order_item_concept_idx ON public.pathology_order_item USING btree (concept_id) WHERE (concept_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS pathology_provider_test_mapping_code_uq ON public.pathology_provider_test_mapping USING btree (provider_id, provider_test_code) WHERE ((provider_test_code IS NOT NULL) AND (mapping_status <> 'retired'::text));
CREATE UNIQUE INDEX IF NOT EXISTS pathology_provider_test_mapping_name_uq ON public.pathology_provider_test_mapping USING btree (provider_id, lower(provider_test_name)) WHERE ((provider_test_code IS NULL) AND (mapping_status <> 'retired'::text));
CREATE INDEX IF NOT EXISTS pathology_provider_test_mapping_concept_idx ON public.pathology_provider_test_mapping USING btree (concept_id);
CREATE INDEX IF NOT EXISTS pathology_provider_test_mapping_verified_by_idx ON public.pathology_provider_test_mapping USING btree (verified_by) WHERE (verified_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_release_policy_updated_by_idx ON public.pathology_release_policy USING btree (updated_by) WHERE (updated_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_practice_status_idx ON public.pathology_result USING btree (practice_id, status, reported_at DESC);
CREATE INDEX IF NOT EXISTS pathology_result_patient_idx ON public.pathology_result USING btree (practice_id, patient_id, reported_at DESC);
CREATE INDEX IF NOT EXISTS pathology_result_order_idx ON public.pathology_result USING btree (order_id);
CREATE INDEX IF NOT EXISTS pathology_result_encounter_idx ON public.pathology_result USING btree (encounter_id) WHERE (encounter_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_provider_idx ON public.pathology_result USING btree (provider_id, received_at DESC);
CREATE INDEX IF NOT EXISTS pathology_result_patient_fk_idx ON public.pathology_result USING btree (patient_id);
CREATE INDEX IF NOT EXISTS pathology_result_created_by_idx ON public.pathology_result USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_correction_of_idx ON public.pathology_result USING btree (correction_of_result_id) WHERE (correction_of_result_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_superseded_by_idx ON public.pathology_result USING btree (superseded_by_result_id) WHERE (superseded_by_result_id IS NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS pathology_result_external_current_uq ON public.pathology_result USING btree (provider_id, external_result_ref) WHERE ((external_result_ref IS NOT NULL) AND is_current);
CREATE INDEX IF NOT EXISTS pathology_ack_practice_idx ON public.pathology_result_acknowledgement USING btree (practice_id, acknowledged_at DESC);
CREATE INDEX IF NOT EXISTS pathology_ack_user_idx ON public.pathology_result_acknowledgement USING btree (acknowledged_by);
CREATE INDEX IF NOT EXISTS pathology_doc_practice_idx ON public.pathology_result_document USING btree (practice_id, result_id);
CREATE INDEX IF NOT EXISTS pathology_doc_created_by_idx ON public.pathology_result_document USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_document_result_fk_idx ON public.pathology_result_document USING btree (result_id);
CREATE UNIQUE INDEX IF NOT EXISTS pathology_result_inbox_external_uq ON public.pathology_result_inbox USING btree (provider_id, external_result_ref) WHERE (external_result_ref IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_inbox_practice_status_idx ON public.pathology_result_inbox USING btree (practice_id, status, received_at DESC);
CREATE INDEX IF NOT EXISTS pathology_result_inbox_patient_idx ON public.pathology_result_inbox USING btree (patient_id, received_at DESC) WHERE (patient_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_inbox_order_idx ON public.pathology_result_inbox USING btree (matched_order_id) WHERE (matched_order_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_inbox_provider_idx ON public.pathology_result_inbox USING btree (provider_id, received_at DESC);
CREATE INDEX IF NOT EXISTS pathology_result_inbox_interface_idx ON public.pathology_result_inbox USING btree (interface_id) WHERE (interface_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_inbox_matched_by_idx ON public.pathology_result_inbox USING btree (matched_by) WHERE (matched_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_inbox_created_by_idx ON public.pathology_result_inbox USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_item_practice_idx ON public.pathology_result_item USING btree (practice_id, result_id);
CREATE INDEX IF NOT EXISTS pathology_result_item_order_item_idx ON public.pathology_result_item USING btree (order_item_id) WHERE (order_item_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_item_result_fk_idx ON public.pathology_result_item USING btree (result_id);
CREATE INDEX IF NOT EXISTS pathology_result_item_concept_idx ON public.pathology_result_item USING btree (concept_id) WHERE (concept_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_release_practice_status_idx ON public.pathology_result_release USING btree (practice_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_result_release_approved_by_idx ON public.pathology_result_release USING btree (approved_by) WHERE (approved_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_result_release_revoked_by_idx ON public.pathology_result_release USING btree (revoked_by) WHERE (revoked_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_safety_case_open_idx ON public.pathology_safety_case USING btree (practice_id, status, sla_due_at) WHERE (status = 'open'::text);
CREATE INDEX IF NOT EXISTS pathology_safety_case_patient_idx ON public.pathology_safety_case USING btree (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_safety_case_assigned_idx ON public.pathology_safety_case USING btree (assigned_user_id) WHERE (assigned_user_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_safety_event_case_idx ON public.pathology_safety_event USING btree (safety_case_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS pathology_safety_event_actor_idx ON public.pathology_safety_event USING btree (actor_user_id) WHERE (actor_user_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_safety_event_practice_idx ON public.pathology_safety_event USING btree (practice_id, occurred_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS pathology_specimen_identifier_uq ON public.pathology_specimen USING btree (practice_id, specimen_identifier) WHERE (specimen_identifier IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_specimen_order_idx ON public.pathology_specimen USING btree (order_id, created_at);
CREATE INDEX IF NOT EXISTS pathology_specimen_patient_idx ON public.pathology_specimen USING btree (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS pathology_specimen_created_by_idx ON public.pathology_specimen USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_specimen_event_specimen_idx ON public.pathology_specimen_event USING btree (specimen_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS pathology_specimen_event_actor_idx ON public.pathology_specimen_event USING btree (actor_user_id) WHERE (actor_user_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_specimen_event_practice_idx ON public.pathology_specimen_event USING btree (practice_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS pathology_test_concept_loinc_idx ON public.pathology_test_concept USING btree (loinc_code) WHERE (loinc_code IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_test_concept_created_by_idx ON public.pathology_test_concept USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS pathology_test_concept_verified_by_idx ON public.pathology_test_concept USING btree (verified_by) WHERE (verified_by IS NOT NULL);

alter table public."pathology_ai_review" enable row level security;
revoke all on public."pathology_ai_review" from anon, authenticated;
grant select on public."pathology_ai_review" to authenticated;
create policy "pathology_ai_review_accept" on public."pathology_ai_review" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (status = 'completed'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_ai_review.practice_id) AND m.active AND (m.role = 'practitioner'::practice_staff_role)))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (status = ANY (ARRAY['clinician_accepted'::text, 'discarded'::text])) AND (reviewed_by = ( SELECT auth.uid() AS uid)) AND (reviewed_at IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_ai_review.practice_id) AND m.active AND (m.role = 'practitioner'::practice_staff_role))))));
create policy "pathology_ai_review_read" on public."pathology_ai_review" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_ai_review.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."pathology_ai_review_source" enable row level security;
revoke all on public."pathology_ai_review_source" from anon, authenticated;
grant select on public."pathology_ai_review_source" to authenticated;
create policy "pathology_ai_review_source_read" on public."pathology_ai_review_source" for select to authenticated using ((EXISTS ( SELECT 1
   FROM (pathology_ai_review r
     JOIN practice_staff_member m ON ((m.practice_id = r.practice_id)))
  WHERE ((r.id = pathology_ai_review_source.review_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."pathology_audit_event" enable row level security;
revoke all on public."pathology_audit_event" from anon, authenticated;
grant select on public."pathology_audit_event" to authenticated;
create policy "pathology_audit_clinical_read" on public."pathology_audit_event" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_audit_event.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."pathology_follow_up_action" enable row level security;
revoke all on public."pathology_follow_up_action" from anon, authenticated;
grant insert, select, update on public."pathology_follow_up_action" to authenticated;
create policy "pathology_follow_up_insert" on public."pathology_follow_up_action" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_follow_up_action.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_follow_up_read" on public."pathology_follow_up_action" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_follow_up_action.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_follow_up_update" on public."pathology_follow_up_action" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_follow_up_action.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_follow_up_action.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_order" enable row level security;
revoke all on public."pathology_order" from anon, authenticated;
grant insert, select, update on public."pathology_order" to authenticated;
create policy "pathology_order_clinical_insert" on public."pathology_order" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_order_clinical_read" on public."pathology_order" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_order_clinical_update" on public."pathology_order" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_order_item" enable row level security;
revoke all on public."pathology_order_item" from anon, authenticated;
grant insert, select, update on public."pathology_order_item" to authenticated;
create policy "pathology_order_item_clinical_insert" on public."pathology_order_item" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_order_item_clinical_read" on public."pathology_order_item" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_order_item_clinical_update" on public."pathology_order_item" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_order_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_provider_test_mapping" enable row level security;
revoke all on public."pathology_provider_test_mapping" from anon, authenticated;
grant select on public."pathology_provider_test_mapping" to authenticated;
create policy "pathology_provider_mapping_read" on public."pathology_provider_test_mapping" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND m.active))));
alter table public."pathology_release_policy" enable row level security;
revoke all on public."pathology_release_policy" from anon, authenticated;
grant insert, select, update on public."pathology_release_policy" to authenticated;
create policy "pathology_release_policy_insert" on public."pathology_release_policy" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_release_policy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role])))))));
create policy "pathology_release_policy_read" on public."pathology_release_policy" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_release_policy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_release_policy_update" on public."pathology_release_policy" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_release_policy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_release_policy.practice_id) AND m.active AND (m.role = ANY (ARRAY['practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role])))))));
alter table public."pathology_result" enable row level security;
revoke all on public."pathology_result" from anon, authenticated;
grant insert, select, update on public."pathology_result" to authenticated;
create policy "pathology_result_clinical_insert" on public."pathology_result" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_result_clinical_read" on public."pathology_result" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_result_clinical_update" on public."pathology_result" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_result_acknowledgement" enable row level security;
revoke all on public."pathology_result_acknowledgement" from anon, authenticated;
grant insert, select, update on public."pathology_result_acknowledgement" to authenticated;
create policy "pathology_ack_clinical_insert" on public."pathology_result_acknowledgement" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (acknowledged_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_acknowledgement.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_ack_clinical_read" on public."pathology_result_acknowledgement" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_acknowledgement.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_ack_clinical_update" on public."pathology_result_acknowledgement" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_acknowledgement.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (acknowledged_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_acknowledgement.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_result_document" enable row level security;
revoke all on public."pathology_result_document" from anon, authenticated;
grant insert, select, update on public."pathology_result_document" to authenticated;
create policy "pathology_doc_clinical_insert" on public."pathology_result_document" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_document.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_doc_clinical_read" on public."pathology_result_document" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_document.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_doc_clinical_update" on public."pathology_result_document" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_document.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_document.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_result_inbox" enable row level security;
revoke all on public."pathology_result_inbox" from anon, authenticated;
grant insert, select, update on public."pathology_result_inbox" to authenticated;
create policy "pathology_inbox_insert" on public."pathology_result_inbox" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_inbox.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))) AND ((created_by IS NULL) OR (created_by = ( SELECT auth.uid() AS uid)))));
create policy "pathology_inbox_read" on public."pathology_result_inbox" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_inbox.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_inbox_update" on public."pathology_result_inbox" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_inbox.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_inbox.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_result_item" enable row level security;
revoke all on public."pathology_result_item" from anon, authenticated;
grant insert, select, update on public."pathology_result_item" to authenticated;
create policy "pathology_result_item_clinical_insert" on public."pathology_result_item" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_result_item_clinical_read" on public."pathology_result_item" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_result_item_clinical_update" on public."pathology_result_item" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_item.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_result_release" enable row level security;
revoke all on public."pathology_result_release" from anon, authenticated;
grant insert, select, update on public."pathology_result_release" to authenticated;
create policy "pathology_result_release_insert" on public."pathology_result_release" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_release.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_result_release_read" on public."pathology_result_release" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_release.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_result_release_update" on public."pathology_result_release" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_release.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_result_release.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_safety_case" enable row level security;
revoke all on public."pathology_safety_case" from anon, authenticated;
grant select on public."pathology_safety_case" to authenticated;
create policy "pathology_safety_case_read" on public."pathology_safety_case" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_safety_case.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."pathology_safety_event" enable row level security;
revoke all on public."pathology_safety_event" from anon, authenticated;
grant select on public."pathology_safety_event" to authenticated;
create policy "pathology_safety_event_read" on public."pathology_safety_event" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_safety_event.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."pathology_specimen" enable row level security;
revoke all on public."pathology_specimen" from anon, authenticated;
grant insert, select, update on public."pathology_specimen" to authenticated;
create policy "pathology_specimen_insert" on public."pathology_specimen" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_specimen.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_specimen_read" on public."pathology_specimen" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_specimen.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
create policy "pathology_specimen_update" on public."pathology_specimen" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_specimen.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_specimen.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
alter table public."pathology_specimen_event" enable row level security;
revoke all on public."pathology_specimen_event" from anon, authenticated;
grant select on public."pathology_specimen_event" to authenticated;
create policy "pathology_specimen_event_read" on public."pathology_specimen_event" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = pathology_specimen_event.practice_id) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role]))))));
alter table public."pathology_test_concept" enable row level security;
revoke all on public."pathology_test_concept" from anon, authenticated;
grant select on public."pathology_test_concept" to authenticated;
create policy "pathology_test_concept_read" on public."pathology_test_concept" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND m.active))));
commit;
