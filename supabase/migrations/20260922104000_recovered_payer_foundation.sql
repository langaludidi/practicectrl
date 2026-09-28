-- Reconstructed schema-only payer foundation from the connected project's catalog.
-- The original setup used untracked DDL; this migration restores a replayable baseline.
-- Tariff tables already exist in recorded migrations; no tenant data is copied.
begin;

create table public."payer_contract" (
  "id" uuid not null default gen_random_uuid(),
  "practice_id" uuid not null,
  "practitioner_id" uuid,
  "medical_scheme_id" uuid,
  "medical_scheme_option_id" uuid,
  "administrator_name" text,
  "agreement_type" text not null default 'network'::text,
  "network_status" text,
  "discipline_code" text,
  "provider_number" text,
  "contract_reference" text,
  "version" integer not null default 1,
  "effective_from" date not null,
  "effective_to" date,
  "source_document_id" uuid,
  "status" text not null default 'draft'::text,
  "payment_terms_days" integer,
  "clawback_terms" jsonb not null default '{}'::jsonb,
  "contract_terms" jsonb not null default '{}'::jsonb,
  "approved_by" uuid,
  "approved_at" timestamp with time zone,
  "last_verified_at" timestamp with time zone,
  "created_by" uuid,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

create table public."payer_contract_document" (
  "id" uuid not null default gen_random_uuid(),
  "practice_id" uuid not null,
  "document_type" text not null,
  "title" text not null,
  "storage_bucket" text not null default 'payer-contract-files'::text,
  "storage_path" text,
  "original_filename" text,
  "mime_type" text,
  "byte_size" bigint,
  "sha256" text,
  "extraction_status" text not null default 'pending'::text,
  "proposed_terms" jsonb not null default '{}'::jsonb,
  "review_status" text not null default 'unreviewed'::text,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "uploaded_by" uuid,
  "uploaded_at" timestamp with time zone not null default now(),
  "created_at" timestamp with time zone not null default now(),
  "contract_id" uuid
);

create table public."payer_billing_rule" (
  "id" uuid not null default gen_random_uuid(),
  "practice_id" uuid,
  "contract_id" uuid,
  "practitioner_id" uuid,
  "medical_scheme_id" uuid,
  "medical_scheme_option_id" uuid,
  "administrator_name" text,
  "rule_scope" text not null,
  "rule_type" text not null,
  "code_system" text,
  "code" text,
  "modifier_code" text,
  "tariff_schedule_id" uuid,
  "tariff_rate_id" uuid,
  "calculation_method" text,
  "rate_percent" numeric(9,4),
  "fixed_amount" numeric(14,2),
  "currency" character(3) not null default 'ZAR'::bpchar,
  "rule_value" jsonb not null default '{}'::jsonb,
  "conditions" jsonb not null default '{}'::jsonb,
  "requirements" jsonb not null default '{}'::jsonb,
  "effective_from" date not null,
  "effective_to" date,
  "version" integer not null default 1,
  "source_document_id" uuid,
  "status" text not null default 'draft'::text,
  "approved_by" uuid,
  "approved_at" timestamp with time zone,
  "last_verified_at" timestamp with time zone,
  "created_by" uuid,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now()
);

create table public."payer_rule_resolution" (
  "id" uuid not null default gen_random_uuid(),
  "practice_id" uuid not null,
  "invoice_line_id" uuid,
  "claim_line_id" uuid,
  "practitioner_id" uuid,
  "medical_scheme_id" uuid,
  "medical_scheme_option_id" uuid,
  "service_date" date not null,
  "code_system" text not null,
  "code" text not null,
  "charged_amount" numeric(14,2),
  "reference_amount" numeric(14,2),
  "expected_contractual_amount" numeric(14,2),
  "expected_scheme_amount" numeric(14,2),
  "expected_patient_liability" numeric(14,2),
  "applied_rule_id" uuid,
  "applied_contract_id" uuid,
  "precedence_level" text,
  "confidence" text not null default 'low'::text,
  "decision_trace" jsonb not null default '[]'::jsonb,
  "resolved_at" timestamp with time zone not null default now(),
  "resolved_by" uuid
);

create table public."payer_remittance_variance" (
  "id" uuid not null default gen_random_uuid(),
  "practice_id" uuid not null,
  "claim_line_id" uuid,
  "remittance_line_id" uuid,
  "rule_resolution_id" uuid,
  "expected_amount" numeric(14,2) not null,
  "actual_paid_amount" numeric(14,2) not null,
  "variance_amount" numeric(14,2) generated always as (expected_amount - actual_paid_amount) stored,
  "variance_reason" text,
  "status" text not null default 'unreviewed'::text,
  "notes" text,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now()
);

alter table public."payer_contract" add constraint "payer_contract_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)));
alter table public."payer_contract" add constraint "payer_contract_payment_terms_days_check" CHECK (((payment_terms_days IS NULL) OR (payment_terms_days >= 0)));
alter table public."payer_contract" add constraint "payer_contract_pkey" PRIMARY KEY (id);
alter table public."payer_contract" add constraint "payer_contract_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'in_review'::text, 'approved'::text, 'active'::text, 'superseded'::text, 'expired'::text, 'rejected'::text])));
alter table public."payer_contract" add constraint "payer_contract_version_check" CHECK ((version > 0));
alter table public."payer_contract_document" add constraint "payer_contract_document_byte_size_check" CHECK (((byte_size IS NULL) OR ((byte_size > 0) AND (byte_size <= 20971520))));
alter table public."payer_contract_document" add constraint "payer_contract_document_document_type_check" CHECK ((document_type = ANY (ARRAY['contract'::text, 'tariff_schedule'::text, 'network_agreement'::text, 'scheme_circular'::text, 'billing_notice'::text, 'other'::text])));
alter table public."payer_contract_document" add constraint "payer_contract_document_extraction_status_check" CHECK ((extraction_status = ANY (ARRAY['pending'::text, 'extracting'::text, 'proposed'::text, 'failed'::text, 'reviewed'::text])));
alter table public."payer_contract_document" add constraint "payer_contract_document_pkey" PRIMARY KEY (id);
alter table public."payer_contract_document" add constraint "payer_contract_document_review_status_check" CHECK ((review_status = ANY (ARRAY['unreviewed'::text, 'in_review'::text, 'approved'::text, 'rejected'::text])));
alter table public."payer_contract_document" add constraint "payer_contract_document_storage_bucket_storage_path_key" UNIQUE (storage_bucket, storage_path);
alter table public."payer_billing_rule" add constraint "payer_billing_rule_calculation_method_check" CHECK (((calculation_method IS NULL) OR (calculation_method = ANY (ARRAY['reference_percentage'::text, 'fixed_amount'::text, 'contract_percentage'::text, 'unit_based'::text, 'formula'::text, 'none'::text]))));
alter table public."payer_billing_rule" add constraint "payer_billing_rule_check" CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)));
alter table public."payer_billing_rule" add constraint "payer_billing_rule_check1" CHECK ((((rule_scope = ANY (ARRAY['provider_contract'::text, 'practice_contract'::text])) AND (practice_id IS NOT NULL)) OR (rule_scope <> ALL (ARRAY['provider_contract'::text, 'practice_contract'::text]))));
alter table public."payer_billing_rule" add constraint "payer_billing_rule_check2" CHECK (((rule_scope <> 'provider_contract'::text) OR (practitioner_id IS NOT NULL)));
alter table public."payer_billing_rule" add constraint "payer_billing_rule_pkey" PRIMARY KEY (id);
alter table public."payer_billing_rule" add constraint "payer_billing_rule_rule_scope_check" CHECK ((rule_scope = ANY (ARRAY['provider_contract'::text, 'practice_contract'::text, 'scheme_option'::text, 'scheme'::text, 'administrator'::text, 'default_reference'::text])));
alter table public."payer_billing_rule" add constraint "payer_billing_rule_rule_type_check" CHECK ((rule_type = ANY (ARRAY['tariff'::text, 'authorisation'::text, 'modifier'::text, 'frequency_limit'::text, 'exclusion'::text, 'copayment'::text, 'balance_billing'::text, 'submission_window'::text, 'referral'::text, 'bundle'::text, 'pmb_chronic'::text, 'other'::text])));
alter table public."payer_billing_rule" add constraint "payer_billing_rule_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'proposed'::text, 'approved'::text, 'active'::text, 'superseded'::text, 'expired'::text, 'rejected'::text])));
alter table public."payer_billing_rule" add constraint "payer_billing_rule_version_check" CHECK ((version > 0));
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_confidence_check" CHECK ((confidence = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_pkey" PRIMARY KEY (id);
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_pkey" PRIMARY KEY (id);
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_status_check" CHECK ((status = ANY (ARRAY['unreviewed'::text, 'accepted'::text, 'disputed'::text, 'recovered'::text, 'written_off'::text])));
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_variance_reason_check" CHECK (((variance_reason IS NULL) OR (variance_reason = ANY (ARRAY['tariff_difference'::text, 'code_rejection'::text, 'modifier_omission'::text, 'benefit_exhaustion'::text, 'copayment'::text, 'network_restriction'::text, 'scheme_underpayment'::text, 'contractual_adjustment'::text, 'authorisation'::text, 'other'::text]))));

alter table public."payer_contract" add constraint "payer_contract_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_contract" add constraint "payer_contract_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_contract" add constraint "payer_contract_medical_scheme_id_fkey" FOREIGN KEY (medical_scheme_id) REFERENCES medical_scheme(id) ON DELETE RESTRICT;
alter table public."payer_contract" add constraint "payer_contract_medical_scheme_option_id_fkey" FOREIGN KEY (medical_scheme_option_id) REFERENCES medical_scheme_option(id) ON DELETE RESTRICT;
alter table public."payer_contract" add constraint "payer_contract_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."payer_contract" add constraint "payer_contract_practitioner_id_fkey" FOREIGN KEY (practitioner_id) REFERENCES practitioner_profile(id) ON DELETE RESTRICT;
alter table public."payer_contract" add constraint "payer_contract_source_document_id_fkey" FOREIGN KEY (source_document_id) REFERENCES payer_contract_document(id) ON DELETE RESTRICT;
alter table public."payer_contract_document" add constraint "payer_contract_document_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES payer_contract(id) ON DELETE SET NULL;
alter table public."payer_contract_document" add constraint "payer_contract_document_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."payer_contract_document" add constraint "payer_contract_document_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_contract_document" add constraint "payer_contract_document_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES payer_contract(id) ON DELETE CASCADE;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_medical_scheme_id_fkey" FOREIGN KEY (medical_scheme_id) REFERENCES medical_scheme(id) ON DELETE CASCADE;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_medical_scheme_option_id_fkey" FOREIGN KEY (medical_scheme_option_id) REFERENCES medical_scheme_option(id) ON DELETE CASCADE;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_practitioner_id_fkey" FOREIGN KEY (practitioner_id) REFERENCES practitioner_profile(id) ON DELETE CASCADE;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_source_document_id_fkey" FOREIGN KEY (source_document_id) REFERENCES payer_contract_document(id) ON DELETE RESTRICT;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_tariff_rate_id_fkey" FOREIGN KEY (tariff_rate_id) REFERENCES tariff_rate(id) ON DELETE SET NULL;
alter table public."payer_billing_rule" add constraint "payer_billing_rule_tariff_schedule_id_fkey" FOREIGN KEY (tariff_schedule_id) REFERENCES tariff_schedule(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_applied_contract_id_fkey" FOREIGN KEY (applied_contract_id) REFERENCES payer_contract(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_applied_rule_id_fkey" FOREIGN KEY (applied_rule_id) REFERENCES payer_billing_rule(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_claim_line_id_fkey" FOREIGN KEY (claim_line_id) REFERENCES claim_line(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_invoice_line_id_fkey" FOREIGN KEY (invoice_line_id) REFERENCES billing_invoice_line(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_medical_scheme_id_fkey" FOREIGN KEY (medical_scheme_id) REFERENCES medical_scheme(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_medical_scheme_option_id_fkey" FOREIGN KEY (medical_scheme_option_id) REFERENCES medical_scheme_option(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_practitioner_id_fkey" FOREIGN KEY (practitioner_id) REFERENCES practitioner_profile(id) ON DELETE SET NULL;
alter table public."payer_rule_resolution" add constraint "payer_rule_resolution_resolved_by_fkey" FOREIGN KEY (resolved_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_claim_line_id_fkey" FOREIGN KEY (claim_line_id) REFERENCES claim_line(id) ON DELETE CASCADE;
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_remittance_line_id_fkey" FOREIGN KEY (remittance_line_id) REFERENCES remittance_line(id) ON DELETE CASCADE;
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."payer_remittance_variance" add constraint "payer_remittance_variance_rule_resolution_id_fkey" FOREIGN KEY (rule_resolution_id) REFERENCES payer_rule_resolution(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS payer_contract_lookup_idx ON public.payer_contract USING btree (practice_id, medical_scheme_id, medical_scheme_option_id, practitioner_id, effective_from, effective_to, status);
CREATE INDEX IF NOT EXISTS payer_contract_scheme_idx ON public.payer_contract USING btree (medical_scheme_id);
CREATE INDEX IF NOT EXISTS payer_contract_option_idx ON public.payer_contract USING btree (medical_scheme_option_id);
CREATE INDEX IF NOT EXISTS payer_contract_practitioner_idx ON public.payer_contract USING btree (practitioner_id);
CREATE INDEX IF NOT EXISTS payer_contract_source_document_idx ON public.payer_contract USING btree (source_document_id);
CREATE INDEX IF NOT EXISTS payer_contract_approved_by_idx ON public.payer_contract USING btree (approved_by);
CREATE INDEX IF NOT EXISTS payer_contract_created_by_idx ON public.payer_contract USING btree (created_by);
CREATE INDEX IF NOT EXISTS payer_contract_document_practice_idx ON public.payer_contract_document USING btree (practice_id, review_status);
CREATE UNIQUE INDEX IF NOT EXISTS payer_contract_document_practice_sha256_uq ON public.payer_contract_document USING btree (practice_id, sha256) WHERE (sha256 IS NOT NULL);
CREATE INDEX IF NOT EXISTS payer_contract_document_contract_idx ON public.payer_contract_document USING btree (contract_id);
CREATE INDEX IF NOT EXISTS payer_contract_document_reviewed_by_idx ON public.payer_contract_document USING btree (reviewed_by);
CREATE INDEX IF NOT EXISTS payer_contract_document_uploaded_by_idx ON public.payer_contract_document USING btree (uploaded_by);
CREATE INDEX IF NOT EXISTS payer_rule_lookup_idx ON public.payer_billing_rule USING btree (practice_id, medical_scheme_id, medical_scheme_option_id, practitioner_id, code_system, code, effective_from, effective_to, status);
CREATE INDEX IF NOT EXISTS payer_rule_contract_idx ON public.payer_billing_rule USING btree (contract_id);
CREATE INDEX IF NOT EXISTS payer_rule_practitioner_idx ON public.payer_billing_rule USING btree (practitioner_id);
CREATE INDEX IF NOT EXISTS payer_rule_scheme_idx ON public.payer_billing_rule USING btree (medical_scheme_id);
CREATE INDEX IF NOT EXISTS payer_rule_option_idx ON public.payer_billing_rule USING btree (medical_scheme_option_id);
CREATE INDEX IF NOT EXISTS payer_rule_tariff_schedule_idx ON public.payer_billing_rule USING btree (tariff_schedule_id);
CREATE INDEX IF NOT EXISTS payer_rule_tariff_rate_idx ON public.payer_billing_rule USING btree (tariff_rate_id);
CREATE INDEX IF NOT EXISTS payer_rule_source_document_idx ON public.payer_billing_rule USING btree (source_document_id);
CREATE INDEX IF NOT EXISTS payer_rule_approved_by_idx ON public.payer_billing_rule USING btree (approved_by);
CREATE INDEX IF NOT EXISTS payer_rule_created_by_idx ON public.payer_billing_rule USING btree (created_by);
CREATE INDEX IF NOT EXISTS payer_rule_resolution_practice_idx ON public.payer_rule_resolution USING btree (practice_id, service_date);
CREATE INDEX IF NOT EXISTS payer_resolution_invoice_line_idx ON public.payer_rule_resolution USING btree (invoice_line_id);
CREATE INDEX IF NOT EXISTS payer_resolution_claim_line_idx ON public.payer_rule_resolution USING btree (claim_line_id);
CREATE INDEX IF NOT EXISTS payer_resolution_practitioner_idx ON public.payer_rule_resolution USING btree (practitioner_id);
CREATE INDEX IF NOT EXISTS payer_resolution_scheme_idx ON public.payer_rule_resolution USING btree (medical_scheme_id);
CREATE INDEX IF NOT EXISTS payer_resolution_option_idx ON public.payer_rule_resolution USING btree (medical_scheme_option_id);
CREATE INDEX IF NOT EXISTS payer_resolution_rule_idx ON public.payer_rule_resolution USING btree (applied_rule_id);
CREATE INDEX IF NOT EXISTS payer_resolution_contract_idx ON public.payer_rule_resolution USING btree (applied_contract_id);
CREATE INDEX IF NOT EXISTS payer_resolution_resolved_by_idx ON public.payer_rule_resolution USING btree (resolved_by);
CREATE INDEX IF NOT EXISTS payer_variance_practice_idx ON public.payer_remittance_variance USING btree (practice_id, status, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS payer_variance_line_uq ON public.payer_remittance_variance USING btree (remittance_line_id, claim_line_id) WHERE ((remittance_line_id IS NOT NULL) AND (claim_line_id IS NOT NULL));
CREATE INDEX IF NOT EXISTS payer_variance_claim_line_idx ON public.payer_remittance_variance USING btree (claim_line_id);
CREATE INDEX IF NOT EXISTS payer_variance_rule_resolution_idx ON public.payer_remittance_variance USING btree (rule_resolution_id);
CREATE INDEX IF NOT EXISTS payer_variance_reviewed_by_idx ON public.payer_remittance_variance USING btree (reviewed_by);

alter table public."billing_invoice_line" add column if not exists "reference_amount" numeric(14,2);
alter table public."billing_invoice_line" add column if not exists "expected_contractual_amount" numeric(14,2);
alter table public."billing_invoice_line" add column if not exists "expected_scheme_amount" numeric(14,2);
alter table public."billing_invoice_line" add column if not exists "expected_patient_liability" numeric(14,2);
alter table public."billing_invoice_line" add column if not exists "payer_rule_resolution_id" uuid;
alter table public."claim_line" add column if not exists "expected_contractual_amount" numeric(14,2);
alter table public."claim_line" add column if not exists "expected_scheme_amount" numeric(14,2);
alter table public."claim_line" add column if not exists "payer_rule_resolution_id" uuid;
alter table public."billing_invoice_line" add constraint "billing_invoice_line_payer_rule_resolution_id_fkey" foreign key (payer_rule_resolution_id) references public.payer_rule_resolution(id) on delete set null;
alter table public."claim_line" add constraint "claim_line_payer_rule_resolution_id_fkey" foreign key (payer_rule_resolution_id) references public.payer_rule_resolution(id) on delete set null;

alter table public."payer_contract" enable row level security;
revoke all on public."payer_contract" from anon, authenticated;
grant select on public."payer_contract" to authenticated;
create policy "payer_contract_staff_read" on public."payer_contract" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = payer_contract.practice_id) AND m.active))));
alter table public."payer_contract_document" enable row level security;
revoke all on public."payer_contract_document" from anon, authenticated;
grant select on public."payer_contract_document" to authenticated;
create policy "payer_contract_document_staff_read" on public."payer_contract_document" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = payer_contract_document.practice_id) AND m.active))));
alter table public."payer_billing_rule" enable row level security;
revoke all on public."payer_billing_rule" from anon, authenticated;
grant select on public."payer_billing_rule" to authenticated;
create policy "payer_rule_staff_read" on public."payer_billing_rule" for select to authenticated using (((practice_id IS NULL) OR (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = payer_billing_rule.practice_id) AND m.active)))));
alter table public."payer_rule_resolution" enable row level security;
revoke all on public."payer_rule_resolution" from anon, authenticated;
grant select on public."payer_rule_resolution" to authenticated;
create policy "payer_resolution_staff_read" on public."payer_rule_resolution" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = payer_rule_resolution.practice_id) AND m.active))));
alter table public."payer_remittance_variance" enable row level security;
revoke all on public."payer_remittance_variance" from anon, authenticated;
grant select on public."payer_remittance_variance" to authenticated;
create policy "payer_variance_staff_read" on public."payer_remittance_variance" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = payer_remittance_variance.practice_id) AND m.active))));

CREATE OR REPLACE FUNCTION private.create_payer_contract_draft_internal(p_practice_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=(select auth.uid());v_id uuid;v_doc uuid;v_pract uuid;v_scheme uuid;v_option uuid;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in('billing','practice_manager','system_admin')) then raise exception 'Contract management role required';end if;
 v_doc:=nullif(p_payload->>'source_document_id','')::uuid;v_pract:=nullif(p_payload->>'practitioner_id','')::uuid;v_scheme:=nullif(p_payload->>'medical_scheme_id','')::uuid;v_option:=nullif(p_payload->>'medical_scheme_option_id','')::uuid;
 if v_doc is not null and not exists(select 1 from public.payer_contract_document d where d.id=v_doc and d.practice_id=p_practice_id) then raise exception 'Source document does not belong to selected practice';end if;
 if v_pract is not null and not exists(select 1 from public.practitioner_profile p where p.id=v_pract and p.practice_id=p_practice_id and p.active) then raise exception 'Practitioner does not belong to selected practice';end if;
 if v_option is not null and not exists(select 1 from public.medical_scheme_option o where o.id=v_option and o.medical_scheme_id=v_scheme) then raise exception 'Scheme option does not belong to scheme';end if;
 if nullif(p_payload->>'effective_from','') is null then raise exception 'Effective start date is required';end if;
 insert into public.payer_contract(practice_id,practitioner_id,medical_scheme_id,medical_scheme_option_id,administrator_name,agreement_type,network_status,discipline_code,provider_number,contract_reference,version,effective_from,effective_to,source_document_id,status,payment_terms_days,clawback_terms,contract_terms,created_by)
 values(p_practice_id,v_pract,v_scheme,v_option,nullif(trim(p_payload->>'administrator_name'),''),coalesce(nullif(trim(p_payload->>'agreement_type'),''),'network'),nullif(trim(p_payload->>'network_status'),''),nullif(trim(p_payload->>'discipline_code'),''),nullif(trim(p_payload->>'provider_number'),''),nullif(trim(p_payload->>'contract_reference'),''),coalesce((p_payload->>'version')::int,1),(p_payload->>'effective_from')::date,nullif(p_payload->>'effective_to','')::date,v_doc,'draft',nullif(p_payload->>'payment_terms_days','')::int,coalesce(p_payload->'clawback_terms','{}'::jsonb),coalesce(p_payload->'contract_terms','{}'::jsonb),v_user)
 returning id into v_id;
 if v_doc is not null then update public.payer_contract_document set contract_id=v_id where id=v_doc;end if;
 return v_id;
end $function$
;
revoke all on function private.create_payer_contract_draft_internal(uuid,jsonb) from public, anon;
grant execute on function private.create_payer_contract_draft_internal(uuid,jsonb) to authenticated;
CREATE OR REPLACE FUNCTION private.create_payer_rule_proposal_internal(p_contract_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=(select auth.uid());c public.payer_contract%rowtype;v_id uuid;v_scope text;v_type text;v_doc uuid;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
 select * into c from public.payer_contract where id=p_contract_id;if not found then raise exception 'Contract not found';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=c.practice_id and m.active and m.role in('billing','practice_manager','system_admin')) then raise exception 'Contract management role required';end if;
 v_scope:=coalesce(nullif(p_payload->>'rule_scope',''),case when c.practitioner_id is not null then 'provider_contract' else 'practice_contract' end);
 if v_scope not in('provider_contract','practice_contract') then raise exception 'Tenant contract rules must use provider_contract or practice_contract scope';end if;
 if v_scope='provider_contract' and c.practitioner_id is null then raise exception 'Provider contract rule requires practitioner';end if;
 v_type:=p_payload->>'rule_type';
 if v_type not in('tariff','authorisation','modifier','frequency_limit','exclusion','copayment','balance_billing','submission_window','referral','bundle','pmb_chronic','other') then raise exception 'Invalid rule type';end if;
 v_doc:=coalesce(nullif(p_payload->>'source_document_id','')::uuid,c.source_document_id);
 if v_doc is null or not exists(select 1 from public.payer_contract_document d where d.id=v_doc and d.practice_id=c.practice_id) then raise exception 'Rule requires a source document from the selected practice';end if;
 insert into public.payer_billing_rule(practice_id,contract_id,practitioner_id,medical_scheme_id,medical_scheme_option_id,administrator_name,rule_scope,rule_type,code_system,code,modifier_code,tariff_schedule_id,tariff_rate_id,calculation_method,rate_percent,fixed_amount,currency,rule_value,conditions,requirements,effective_from,effective_to,version,source_document_id,status,created_by)
 values(c.practice_id,c.id,c.practitioner_id,c.medical_scheme_id,c.medical_scheme_option_id,c.administrator_name,v_scope,v_type,nullif(trim(p_payload->>'code_system'),''),nullif(trim(p_payload->>'code'),''),nullif(trim(p_payload->>'modifier_code'),''),nullif(p_payload->>'tariff_schedule_id','')::uuid,nullif(p_payload->>'tariff_rate_id','')::uuid,nullif(p_payload->>'calculation_method',''),nullif(p_payload->>'rate_percent','')::numeric,nullif(p_payload->>'fixed_amount','')::numeric,coalesce(nullif(p_payload->>'currency',''),'ZAR'),coalesce(p_payload->'rule_value','{}'::jsonb),coalesce(p_payload->'conditions','{}'::jsonb),coalesce(p_payload->'requirements','{}'::jsonb),coalesce(nullif(p_payload->>'effective_from','')::date,c.effective_from),coalesce(nullif(p_payload->>'effective_to','')::date,c.effective_to),coalesce((p_payload->>'version')::int,c.version),v_doc,'proposed',v_user)
 returning id into v_id;
 return v_id;
end $function$
;
revoke all on function private.create_payer_rule_proposal_internal(uuid,jsonb) from public, anon;
grant execute on function private.create_payer_rule_proposal_internal(uuid,jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.resolve_payer_billing_rule(p_practice_id uuid, p_practitioner_id uuid, p_scheme_id uuid, p_option_id uuid, p_code_system text, p_code text, p_service_date date, p_reference_amount numeric, p_charged_amount numeric, p_quantity numeric DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.payer_billing_rule%rowtype; v_expected numeric; v_patient numeric:=0; req jsonb:='[]'::jsonb; v_conf text:='low';
begin
 if not exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=p_practice_id and m.active) then raise exception 'Practice access required';end if;
 select x.* into r from public.payer_billing_rule x
 left join public.payer_contract c on c.id=x.contract_id
 where x.status='active'
   and x.rule_type='tariff'
   and p_service_date>=x.effective_from and (x.effective_to is null or p_service_date<=x.effective_to)
   and (x.code_system is null or lower(x.code_system)=lower(p_code_system))
   and (x.code is null or x.code=p_code)
   and (x.medical_scheme_id is null or x.medical_scheme_id=p_scheme_id)
   and (x.medical_scheme_option_id is null or x.medical_scheme_option_id=p_option_id)
   and (x.practitioner_id is null or x.practitioner_id=p_practitioner_id)
   and (
     (x.rule_scope in('provider_contract','practice_contract') and x.practice_id=p_practice_id)
     or (x.rule_scope not in('provider_contract','practice_contract') and (x.practice_id is null or x.practice_id=p_practice_id))
   )
   and (c.id is null or (c.status='active' and p_service_date>=c.effective_from and (c.effective_to is null or p_service_date<=c.effective_to)))
 order by
   case x.rule_scope when 'provider_contract' then 1 when 'practice_contract' then 2 when 'scheme_option' then 3 when 'scheme' then 4 when 'administrator' then 5 else 6 end,
   case when x.code=p_code then 0 else 1 end,
   x.version desc,x.effective_from desc
 limit 1;

 if r.id is not null then
   v_expected:=case r.calculation_method
     when 'reference_percentage' then round(coalesce(p_reference_amount,0)*coalesce(r.rate_percent,100)/100,2)
     when 'contract_percentage' then round(coalesce(p_reference_amount,p_charged_amount,0)*coalesce(r.rate_percent,100)/100,2)
     when 'fixed_amount' then round(coalesce(r.fixed_amount,0),2)
     when 'unit_based' then round(coalesce(r.fixed_amount,0)*coalesce(p_quantity,1),2)
     else null end;
   v_conf:=case when r.rule_scope in('provider_contract','practice_contract') and r.source_document_id is not null and r.last_verified_at is not null then 'high'
                when r.source_document_id is not null then 'medium' else 'low' end;
 end if;

 select coalesce(jsonb_agg(jsonb_build_object('rule_id',q.id,'rule_type',q.rule_type,'requirements',q.requirements,'rule_value',q.rule_value,'scope',q.rule_scope) order by
 case q.rule_scope when 'provider_contract' then 1 when 'practice_contract' then 2 when 'scheme_option' then 3 when 'scheme' then 4 when 'administrator' then 5 else 6 end),'[]'::jsonb)
 into req
 from public.payer_billing_rule q
 left join public.payer_contract qc on qc.id=q.contract_id
 where q.status='active' and q.rule_type<>'tariff'
   and p_service_date>=q.effective_from and (q.effective_to is null or p_service_date<=q.effective_to)
   and (q.code_system is null or lower(q.code_system)=lower(p_code_system))
   and (q.code is null or q.code=p_code)
   and (q.medical_scheme_id is null or q.medical_scheme_id=p_scheme_id)
   and (q.medical_scheme_option_id is null or q.medical_scheme_option_id=p_option_id)
   and (q.practitioner_id is null or q.practitioner_id=p_practitioner_id)
   and ((q.rule_scope in('provider_contract','practice_contract') and q.practice_id=p_practice_id) or (q.rule_scope not in('provider_contract','practice_contract') and (q.practice_id is null or q.practice_id=p_practice_id)))
   and (qc.id is null or (qc.status='active' and p_service_date>=qc.effective_from and (qc.effective_to is null or p_service_date<=qc.effective_to)));

 if v_expected is not null then v_patient:=greatest(coalesce(p_charged_amount,0)-v_expected,0);end if;
 return jsonb_build_object(
  'matched',r.id is not null,'applied_rule_id',r.id,'applied_contract_id',r.contract_id,'precedence_level',r.rule_scope,
  'reference_amount',p_reference_amount,'charged_amount',p_charged_amount,'expected_contractual_amount',v_expected,
  'expected_scheme_amount',v_expected,'estimated_patient_liability',case when v_expected is null then null else v_patient end,
  'calculation_method',r.calculation_method,'rate_percent',r.rate_percent,'fixed_amount',r.fixed_amount,
  'requirements',req,'confidence',v_conf,'effective_date',p_service_date,
  'source_document_id',r.source_document_id
 );
end $function$
;
revoke all on function public.resolve_payer_billing_rule(uuid,uuid,uuid,uuid,text,text,date,numeric,numeric,numeric) from public, anon;
grant execute on function public.resolve_payer_billing_rule(uuid,uuid,uuid,uuid,text,text,date,numeric,numeric,numeric) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.create_payer_contract_draft(p_practice_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.create_payer_contract_draft_internal(p_practice_id,p_payload)$function$
;
revoke all on function public.create_payer_contract_draft(uuid,jsonb) from public, anon;
grant execute on function public.create_payer_contract_draft(uuid,jsonb) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.create_payer_rule_proposal(p_contract_id uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$select private.create_payer_rule_proposal_internal(p_contract_id,p_payload)$function$
;
revoke all on function public.create_payer_rule_proposal(uuid,jsonb) from public, anon;
grant execute on function public.create_payer_rule_proposal(uuid,jsonb) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.preview_invoice_line_payer_resolution(p_invoice_line_id uuid, p_practitioner_id uuid DEFAULT NULL::uuid, p_reference_amount numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
 l public.billing_invoice_line%rowtype;i public.billing_invoice%rowtype;r public.payer_billing_rule%rowtype;
 v_reference numeric;v_expected numeric;v_patient numeric:=0;v_contract_applicable boolean:=false;v_contract public.payer_contract%rowtype;
 req jsonb:='[]'::jsonb;v_conf text:='low';v_matched boolean:=false;
begin
 select * into l from public.billing_invoice_line where id=p_invoice_line_id;if not found then raise exception 'Invoice line not found or inaccessible';end if;
 select * into i from public.billing_invoice where id=l.invoice_id;if not found then raise exception 'Invoice not found or inaccessible';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=i.practice_id and m.active) then raise exception 'Practice access required';end if;
 if p_practitioner_id is not null and not exists(select 1 from public.practitioner_profile p where p.id=p_practitioner_id and p.practice_id=i.practice_id and p.active) then raise exception 'Practitioner does not belong to selected practice';end if;
 v_reference:=p_reference_amount;if v_reference is null and l.tariff_rate_id is not null then select tr.amount into v_reference from public.tariff_rate tr where tr.id=l.tariff_rate_id;end if;

 if i.payer_contract_id is not null then
   select * into v_contract from public.payer_contract pc where pc.id=i.payer_contract_id and pc.practice_id=i.practice_id and pc.status='active'
    and coalesce(l.service_date,i.invoice_date)>=pc.effective_from and (pc.effective_to is null or coalesce(l.service_date,i.invoice_date)<=pc.effective_to)
    and (pc.practitioner_id is null or pc.practitioner_id=p_practitioner_id);
 else
   select * into v_contract from public.payer_contract pc where pc.practice_id=i.practice_id and pc.status='active'
    and i.medical_scheme_id is not null and pc.medical_scheme_id=i.medical_scheme_id
    and (pc.medical_scheme_option_id is null or pc.medical_scheme_option_id=i.medical_scheme_option_id)
    and (pc.practitioner_id is null or pc.practitioner_id=p_practitioner_id)
    and coalesce(l.service_date,i.invoice_date)>=pc.effective_from and (pc.effective_to is null or coalesce(l.service_date,i.invoice_date)<=pc.effective_to)
    order by case when pc.practitioner_id is not null then 1 else 2 end,case when pc.medical_scheme_option_id is not null then 1 else 2 end,pc.version desc,pc.effective_from desc limit 1;
 end if;
 v_contract_applicable:=v_contract.id is not null;

 if v_contract_applicable then
   select x.* into r from public.payer_billing_rule x where x.contract_id=v_contract.id and x.status='active' and x.rule_type='tariff'
    and coalesce(l.service_date,i.invoice_date)>=x.effective_from and (x.effective_to is null or coalesce(l.service_date,i.invoice_date)<=x.effective_to)
    and (x.code_system is null or lower(x.code_system)=lower(l.code_system)) and (x.code is null or x.code=l.code)
    and (x.practitioner_id is null or x.practitioner_id=p_practitioner_id)
    order by case when x.code=l.code then 0 else 1 end,x.version desc,x.effective_from desc limit 1;
   v_matched:=r.id is not null;
   if v_matched then
     v_expected:=case r.calculation_method when 'reference_percentage' then case when v_reference is null then null else round(v_reference*coalesce(r.rate_percent,100)/100,2) end
       when 'contract_percentage' then round(coalesce(v_reference,l.line_amount,0)*coalesce(r.rate_percent,100)/100,2)
       when 'fixed_amount' then round(coalesce(r.fixed_amount,0),2)
       when 'unit_based' then round(coalesce(r.fixed_amount,0)*coalesce(l.quantity,1),2) else null end;
     v_conf:=case when r.source_document_id is not null and r.last_verified_at is not null and v_contract.last_verified_at is not null then 'high' when r.source_document_id is not null then 'medium' else 'low' end;
   end if;
   select coalesce(jsonb_agg(jsonb_build_object('rule_id',q.id,'rule_type',q.rule_type,'requirements',q.requirements,'rule_value',q.rule_value,'scope',q.rule_scope) order by q.rule_type),'[]'::jsonb) into req
   from public.payer_billing_rule q where q.contract_id=v_contract.id and q.status='active' and q.rule_type<>'tariff'
    and coalesce(l.service_date,i.invoice_date)>=q.effective_from and (q.effective_to is null or coalesce(l.service_date,i.invoice_date)<=q.effective_to)
    and (q.code_system is null or lower(q.code_system)=lower(l.code_system)) and (q.code is null or q.code=l.code)
    and (q.practitioner_id is null or q.practitioner_id=p_practitioner_id);
 else
   if i.medical_scheme_id is not null then
     return public.resolve_payer_billing_rule(i.practice_id,p_practitioner_id,i.medical_scheme_id,i.medical_scheme_option_id,l.code_system,l.code,coalesce(l.service_date,i.invoice_date),v_reference,l.line_amount,l.quantity)
       || jsonb_build_object('invoice_id',i.id,'invoice_number',i.invoice_number,'invoice_line_id',l.id,'line_no',l.line_no,'description',l.description_snapshot,'service_date',coalesce(l.service_date,i.invoice_date),'claim_eligible',l.claim_eligible,'contract_applicable',false,'resolution_required',false,'selected_contract_id',i.payer_contract_id);
   end if;
 end if;

 if v_expected is not null then v_patient:=greatest(coalesce(l.line_amount,0)-v_expected,0);end if;
 return jsonb_build_object(
  'matched',v_matched,'contract_applicable',v_contract_applicable,'resolution_required',v_contract_applicable and l.claim_eligible,
  'invoice_id',i.id,'invoice_number',i.invoice_number,'invoice_line_id',l.id,'line_no',l.line_no,'description',l.description_snapshot,
  'code_system',l.code_system,'code',l.code,'modifier_codes',l.modifier_codes,'diagnosis_codes',l.diagnosis_codes,'service_date',coalesce(l.service_date,i.invoice_date),'quantity',l.quantity,'claim_eligible',l.claim_eligible,
  'charged_amount',l.line_amount,'reference_amount',v_reference,'expected_contractual_amount',v_expected,'expected_scheme_amount',v_expected,'estimated_patient_liability',case when v_expected is null then null else v_patient end,
  'applied_rule_id',r.id,'applied_contract_id',v_contract.id,'precedence_level',case when v_contract.practitioner_id is not null then 'provider_contract' else 'practice_contract' end,
  'calculation_method',r.calculation_method,'rate_percent',r.rate_percent,'fixed_amount',r.fixed_amount,'requirements',req,'confidence',v_conf,'source_document_id',r.source_document_id,
  'contract',jsonb_build_object('contract_reference',v_contract.contract_reference,'agreement_type',v_contract.agreement_type,'network_status',v_contract.network_status,'provider_number',v_contract.provider_number,'discipline_code',v_contract.discipline_code,'effective_from',v_contract.effective_from,'effective_to',v_contract.effective_to,'administrator_name',v_contract.administrator_name)
 );
end $function$
;
revoke all on function public.preview_invoice_line_payer_resolution(uuid,uuid,numeric) from public, anon;
grant execute on function public.preview_invoice_line_payer_resolution(uuid,uuid,numeric) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.record_invoice_line_payer_resolution(p_invoice_line_id uuid, p_practitioner_id uuid, p_reference_amount numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
 v_user uuid:=(select auth.uid());
 l public.billing_invoice_line%rowtype;
 i public.billing_invoice%rowtype;
 j jsonb;
 v_id uuid;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
 select * into l from public.billing_invoice_line where id=p_invoice_line_id for update;if not found then raise exception 'Invoice line not found';end if;
 select * into i from public.billing_invoice where id=l.invoice_id;if not found then raise exception 'Invoice not found';end if;
 if i.status<>'draft' then raise exception 'Payer resolution can only be recorded while the invoice is draft';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=i.practice_id and m.active and m.role in('billing','practice_manager','clinical_admin','system_admin')) then raise exception 'Billing role required';end if;

 j:=public.preview_invoice_line_payer_resolution(l.id,p_practitioner_id,p_reference_amount);
 if coalesce((j->>'contract_applicable')::boolean,false) and coalesce((j->>'matched')::boolean,false)=false
    and coalesce(jsonb_array_length(j->'requirements'),0)=0 then
   raise exception 'An active payer agreement applies but no effective billing rule matched this line';
 end if;

 insert into public.payer_rule_resolution(
   practice_id,invoice_line_id,practitioner_id,medical_scheme_id,medical_scheme_option_id,
   service_date,code_system,code,charged_amount,reference_amount,expected_contractual_amount,
   expected_scheme_amount,expected_patient_liability,applied_rule_id,applied_contract_id,
   precedence_level,confidence,decision_trace,resolved_by
 )
 values(
   i.practice_id,l.id,p_practitioner_id,i.medical_scheme_id,i.medical_scheme_option_id,
   coalesce(l.service_date,i.invoice_date),l.code_system,l.code,l.line_amount,
   nullif(j->>'reference_amount','')::numeric,nullif(j->>'expected_contractual_amount','')::numeric,
   nullif(j->>'expected_scheme_amount','')::numeric,nullif(j->>'estimated_patient_liability','')::numeric,
   nullif(j->>'applied_rule_id','')::uuid,nullif(j->>'applied_contract_id','')::uuid,
   j->>'precedence_level',coalesce(j->>'confidence','low'),jsonb_build_array(j),v_user
 ) returning id into v_id;

 update public.billing_invoice_line
 set reference_amount=nullif(j->>'reference_amount','')::numeric,
     expected_contractual_amount=nullif(j->>'expected_contractual_amount','')::numeric,
     expected_scheme_amount=nullif(j->>'expected_scheme_amount','')::numeric,
     expected_patient_liability=nullif(j->>'estimated_patient_liability','')::numeric,
     payer_rule_resolution_id=v_id
 where id=l.id;

 insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
 values(i.id,'validated',v_user,jsonb_build_object(
   'payer_resolution_id',v_id,'invoice_line_id',l.id,'line_no',l.line_no,
   'contract_id',j->'applied_contract_id','rule_id',j->'applied_rule_id',
   'expected_scheme_amount',j->'expected_scheme_amount','expected_patient_liability',j->'estimated_patient_liability',
   'confidence',j->'confidence'
 ));
 return v_id;
end $function$
;
revoke all on function public.record_invoice_line_payer_resolution(uuid,uuid,numeric) from public, anon;
grant execute on function public.record_invoice_line_payer_resolution(uuid,uuid,numeric) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.simulate_payer_contract_payment(p_practice_id uuid, p_contract_id uuid, p_practitioner_id uuid, p_code_system text, p_code text, p_service_date date, p_reference_amount numeric, p_charged_amount numeric, p_quantity numeric DEFAULT 1, p_modifier_codes text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid := (select auth.uid());
  c public.payer_contract%rowtype;
  tr public.payer_billing_rule%rowtype;
  v_expected numeric;
  v_patient numeric;
  v_requirements jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_missing_modifiers text[] := '{}';
  v_confidence text := 'low';
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('billing','practice_manager','clinical_admin','system_admin','auditor','practitioner')
  ) then raise exception 'Practice access required'; end if;
  if p_service_date is null then raise exception 'Service date is required'; end if;
  if length(trim(coalesce(p_code_system,'')))<1 or length(trim(coalesce(p_code,'')))<1 then raise exception 'Code system and code are required'; end if;
  if coalesce(p_charged_amount,-1)<0 or coalesce(p_quantity,0)<=0 then raise exception 'Charged amount and quantity are invalid'; end if;

  select * into c from public.payer_contract
  where id=p_contract_id and practice_id=p_practice_id;
  if not found then raise exception 'Payer contract not found in selected practice'; end if;
  if c.status not in ('draft','in_review','approved','active') then raise exception 'Contract is not available for simulation'; end if;
  if p_service_date<c.effective_from or (c.effective_to is not null and p_service_date>c.effective_to) then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('code','CONTRACT_OUTSIDE_EFFECTIVE_DATE','message','The selected contract is not effective on the service date'));
  end if;
  if c.practitioner_id is not null and c.practitioner_id is distinct from p_practitioner_id then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('code','PROVIDER_MISMATCH','message','This provider-specific agreement does not match the selected practitioner'));
  end if;

  select r.* into tr
  from public.payer_billing_rule r
  where r.contract_id=c.id
    and r.status in ('proposed','approved','active')
    and r.rule_type='tariff'
    and p_service_date>=r.effective_from and (r.effective_to is null or p_service_date<=r.effective_to)
    and (r.code_system is null or lower(r.code_system)=lower(p_code_system))
    and (r.code is null or r.code=p_code)
    and (r.practitioner_id is null or r.practitioner_id=p_practitioner_id)
  order by
    case when r.practitioner_id is not null then 0 else 1 end,
    case when r.code=p_code then 0 else 1 end,
    r.version desc,r.effective_from desc
  limit 1;

  if tr.id is not null then
    v_expected:=case tr.calculation_method
      when 'reference_percentage' then case when p_reference_amount is null then null else round(p_reference_amount*coalesce(tr.rate_percent,100)/100,2) end
      when 'contract_percentage' then round(coalesce(p_reference_amount,p_charged_amount,0)*coalesce(tr.rate_percent,100)/100,2)
      when 'fixed_amount' then round(coalesce(tr.fixed_amount,0),2)
      when 'unit_based' then round(coalesce(tr.fixed_amount,0)*coalesce(p_quantity,1),2)
      else null end;
    v_confidence:=case
      when tr.source_document_id is not null and tr.last_verified_at is not null and c.last_verified_at is not null then 'high'
      when tr.source_document_id is not null then 'medium'
      else 'low' end;
  else
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('code','NO_TARIFF_RULE','message','No effective tariff rule matched this contract, provider and service'));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'rule_id',r.id,'rule_type',r.rule_type,'status',r.status,'modifier_code',r.modifier_code,
    'requirements',r.requirements,'rule_value',r.rule_value,'conditions',r.conditions
  ) order by r.rule_type),'[]'::jsonb)
  into v_requirements
  from public.payer_billing_rule r
  where r.contract_id=c.id
    and r.status in ('proposed','approved','active')
    and r.rule_type<>'tariff'
    and p_service_date>=r.effective_from and (r.effective_to is null or p_service_date<=r.effective_to)
    and (r.code_system is null or lower(r.code_system)=lower(p_code_system))
    and (r.code is null or r.code=p_code)
    and (r.practitioner_id is null or r.practitioner_id=p_practitioner_id);

  select coalesce(array_agg(distinct coalesce(nullif(r.modifier_code,''),nullif(r.rule_value->>'modifier_code',''))),'{}'::text[])
  into v_missing_modifiers
  from public.payer_billing_rule r
  where r.contract_id=c.id and r.status in ('proposed','approved','active')
    and r.rule_type='modifier'
    and p_service_date>=r.effective_from and (r.effective_to is null or p_service_date<=r.effective_to)
    and (r.code_system is null or lower(r.code_system)=lower(p_code_system))
    and (r.code is null or r.code=p_code)
    and coalesce(nullif(r.modifier_code,''),nullif(r.rule_value->>'modifier_code','')) is not null
    and not (coalesce(nullif(r.modifier_code,''),nullif(r.rule_value->>'modifier_code','')) = any(coalesce(p_modifier_codes,'{}'::text[])));

  if coalesce(cardinality(v_missing_modifiers),0)>0 then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('code','MISSING_MODIFIER','message','One or more contract modifiers are not present','modifiers',to_jsonb(v_missing_modifiers)));
  end if;

  v_patient:=case when v_expected is null then null else greatest(p_charged_amount-v_expected,0) end;

  return jsonb_build_object(
    'simulation_only',true,
    'contract_id',c.id,
    'contract_status',c.status,
    'contract_reference',c.contract_reference,
    'agreement_type',c.agreement_type,
    'network_status',c.network_status,
    'administrator_name',c.administrator_name,
    'provider_number',c.provider_number,
    'service_date',p_service_date,
    'code_system',p_code_system,
    'code',p_code,
    'charged_amount',p_charged_amount,
    'reference_amount',p_reference_amount,
    'expected_contractual_amount',v_expected,
    'expected_scheme_amount',v_expected,
    'estimated_patient_liability',v_patient,
    'tariff_rule_id',tr.id,
    'tariff_rule_status',tr.status,
    'calculation_method',tr.calculation_method,
    'rate_percent',tr.rate_percent,
    'fixed_amount',tr.fixed_amount,
    'requirements',v_requirements,
    'warnings',v_warnings,
    'confidence',v_confidence
  );
end $function$
;
revoke all on function public.simulate_payer_contract_payment(uuid,uuid,uuid,text,text,date,numeric,numeric,numeric,text[]) from public, anon;
grant execute on function public.simulate_payer_contract_payment(uuid,uuid,uuid,text,text,date,numeric,numeric,numeric,text[]) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.approve_payer_contract_document(p_document_id uuid, p_approved boolean, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid());d public.payer_contract_document%rowtype;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
 select * into d from public.payer_contract_document where id=p_document_id for update;if not found then raise exception 'Document not found';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=d.practice_id and m.active and m.role in('practice_manager','clinical_admin','system_admin')) then raise exception 'Contract reviewer role required';end if;
 update public.payer_contract_document set review_status=case when p_approved then 'approved' else 'rejected' end,extraction_status=case when extraction_status='proposed' then 'reviewed' else extraction_status end,reviewed_by=v_user,reviewed_at=now(),proposed_terms=proposed_terms||jsonb_build_object('review_notes',p_notes) where id=p_document_id;
 return p_document_id;
end $function$
;
revoke all on function public.approve_payer_contract_document(uuid,boolean,text) from public, anon;
grant execute on function public.approve_payer_contract_document(uuid,boolean,text) to authenticated, service_role;

commit;
