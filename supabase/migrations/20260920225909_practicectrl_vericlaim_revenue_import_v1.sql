
begin;

create table if not exists public.vericlaim_report_profile (
  report_type text primary key,
  display_name text not null,
  source_system text not null default 'VeriClaim',
  expected_columns text[] not null,
  scope_description text not null,
  authoritative_for text[] not null default '{}',
  not_authoritative_for text[] not null default '{}',
  parser_rules text[] not null default '{}',
  profile_version text not null default '1.0',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.vericlaim_report_profile(report_type,display_name,expected_columns,scope_description,authoritative_for,not_authoritative_for,parser_rules)
values
('AGE_ANALYSIS','Age Analysis',array['Patient','AccNo','FileNo','Scheme','MemberNo','CellNo','WorkNo','Main Member Email Address','120+ Days','90 Days','60 Days','30 Days','Current','Total'],
 'Point-in-time debtor snapshot',array['account_total_outstanding','ageing_buckets','contact_endpoints_at_export'],array['patient_vs_scheme_liability_split'],
 array['Use the latest snapshot for account total and ageing. Do not derive patient-versus-scheme liability from this report alone.']),
('INVOICE_ACTIVITY','Invoice Activity',array['Treatment Date','InvoiceNumber','Patient','Account','Patient Amount','Funder Amount','Total Amount','Received Amount','Paid Amount','Journaled Amount','Journaled Date','Outstanding Amount','Age Days'],
 'Treatment-date-window invoice activity',array['invoice_facts_in_window','patient_and_funder_billed_amounts_in_window','receipts_and_journals_in_window','invoice_outstanding_in_window'],array['whole_book_current_outstanding','whole_book_patient_vs_scheme_liability'],
 array['Journal rows may have blank invoice-identifying columns and inherit the preceding invoice context.','Do not treat every spreadsheet row as a new invoice.']),
('SCHEME_CLAIMS','Claims to Schemes',array['Scheme Name','Invoice No','Invoice Date','Treatment Date','Acc No','File No','Patient Surname','Claimed Amount','Outstanding'],
 'Treatment-date-window scheme claims',array['scheme_claims_inside_selected_window'],array['all_current_scheme_outstanding'],
 array['A windowed scheme-claims extract is evidence, not a complete current liability position.']),
('FUNDER_RECEIPTS','Funder Receipts',array['Medical Scheme','Scheme Option','Capture Date','Receipt Date','Receipt Amount','Receipt Number','Acc No','File No','Patient','Invoice Number','Claim No','Treatment Date','Invoice Date','Scheme Liable','Scheme Paid','Scheme Nett Amount'],
 'Receipt-date-window funder allocations',array['scheme_receipt_allocations_in_window'],array[]::text[],
 array['Receipt Amount repeats across allocation rows for the same Receipt Number.','Deduplicate receipt headers by Receipt Number.','Use Scheme Paid for invoice-level allocation reconciliation.']),
('SCHEME_CREDITS','Scheme Credit Report',array['Scheme','Acc No','File No','Invoice No','Scheme Credit Amount'],
 'All-schemes credit snapshot',array['scheme_invoice_credit_suppression'],array[]::text[],array['Credits suppress automated collection until resolved.']),
('RECEIPT_TYPE_SUMMARY','Receipt Type Summary',array['Payment Type','Received Amount'],
 'Receipt-date-window practice-level receipt KPI',array['practice_level_receipt_kpis_in_window'],array['account_level_recovery_attribution'],array['Do not use summary receipts for account-level allocation.']),
('SCHEME_PATIENT_POPULATION','Patients per Scheme and Option',array['Scheme','Scheme Option','Total Patients'],
 'Reference population',array['scheme_option_population_analytics'],array['collections_workflow'],array['Population analytics only; not a collection or member-eligibility source.'])
on conflict(report_type) do update set
 display_name=excluded.display_name,expected_columns=excluded.expected_columns,scope_description=excluded.scope_description,
 authoritative_for=excluded.authoritative_for,not_authoritative_for=excluded.not_authoritative_for,parser_rules=excluded.parser_rules,updated_at=now();

create table if not exists public.vericlaim_import_batch (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  report_type text not null references public.vericlaim_report_profile(report_type) on delete restrict,
  source_filename text not null,
  source_sha256 text not null check (source_sha256 ~ '^[a-f0-9]{64}$'),
  period_start date,
  period_end date,
  snapshot_at timestamptz,
  status text not null default 'staging' check (status in ('staging','validated','promoted','failed','rejected')),
  row_count integer not null default 0 check (row_count >= 0),
  valid_row_count integer not null default 0 check (valid_row_count >= 0),
  rejected_row_count integer not null default 0 check (rejected_row_count >= 0),
  metrics jsonb not null default '{}'::jsonb,
  validation_summary jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(practice_id,report_type,source_sha256)
);
create index if not exists vericlaim_import_practice_idx on public.vericlaim_import_batch(practice_id,report_type,created_at desc);
create index if not exists vericlaim_import_created_by_idx on public.vericlaim_import_batch(created_by) where created_by is not null;

create table if not exists public.vericlaim_age_analysis_staging (
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete cascade,
  row_number integer not null,
  patient_name text, account_ref text, file_ref text, scheme_name text, member_no_masked text,
  cell_no text, work_no text, email text,
  days_120_plus numeric(14,2), days_90 numeric(14,2), days_60 numeric(14,2), days_30 numeric(14,2), current_amount numeric(14,2), total_amount numeric(14,2),
  parse_status text not null default 'valid' check (parse_status in ('valid','invalid')),
  parse_error text, raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.vericlaim_invoice_activity_staging (
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete cascade,
  row_number integer not null,
  treatment_date date, invoice_number text, patient_name text, account_ref text,
  patient_amount numeric(14,2), funder_amount numeric(14,2), total_amount numeric(14,2), received_amount numeric(14,2), paid_amount numeric(14,2),
  journaled_amount numeric(14,2), journaled_date date, outstanding_amount numeric(14,2), age_days integer,
  inherited_invoice_context boolean not null default false,
  parse_status text not null default 'valid' check (parse_status in ('valid','invalid')),
  parse_error text, raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.vericlaim_scheme_claims_staging (
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete cascade,
  row_number integer not null,
  scheme_name text, invoice_number text, invoice_date date, treatment_date date, account_ref text, file_ref text, patient_surname text,
  claimed_amount numeric(14,2), outstanding_amount numeric(14,2),
  parse_status text not null default 'valid' check (parse_status in ('valid','invalid')),
  parse_error text, raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.vericlaim_funder_receipts_staging (
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete cascade,
  row_number integer not null,
  medical_scheme text, scheme_option text, capture_date date, receipt_date date, receipt_amount numeric(14,2), receipt_number text,
  account_ref text, file_ref text, patient_name text, invoice_number text, claim_number text, treatment_date date, invoice_date date,
  scheme_liable numeric(14,2), scheme_paid numeric(14,2), scheme_nett_amount numeric(14,2),
  parse_status text not null default 'valid' check (parse_status in ('valid','invalid')),
  parse_error text, raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.vericlaim_scheme_population_staging (
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete cascade,
  row_number integer not null,
  scheme_name text, scheme_option text, total_patients integer,
  parse_status text not null default 'valid' check (parse_status in ('valid','invalid')),
  parse_error text, raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.revenue_account_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete restrict,
  snapshot_at timestamptz not null,
  patient_name_snapshot text not null,
  account_ref text,
  file_ref text,
  scheme_name_snapshot text,
  days_120_plus numeric(14,2) not null default 0,
  days_90 numeric(14,2) not null default 0,
  days_60 numeric(14,2) not null default 0,
  days_30 numeric(14,2) not null default 0,
  current_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,
  liability_status text not null default 'unresolved' check (liability_status in ('unresolved','scheme_verified','patient_verified','split_verified','credit','zero_balance')),
  collection_suppressed boolean not null default true,
  suppression_reason text,
  source_freshness_status text not null default 'current' check (source_freshness_status in ('current','stale','superseded')),
  created_at timestamptz not null default now(),
  unique(import_batch_id,account_ref,file_ref,patient_name_snapshot)
);
create index if not exists revenue_account_snapshot_practice_idx on public.revenue_account_snapshot(practice_id,snapshot_at desc,total_amount desc);
create index if not exists revenue_account_snapshot_patient_idx on public.revenue_account_snapshot(patient_id,snapshot_at desc) where patient_id is not null;

create table if not exists public.revenue_collection_case (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  revenue_snapshot_id uuid references public.revenue_account_snapshot(id) on delete restrict,
  account_ref text,
  case_status text not null default 'review_required' check (case_status in ('review_required','ready_for_contact','contacted','arrangement','waiting_scheme','external_recovery','resolved','suppressed','closed')),
  liability_status text not null default 'unresolved' check (liability_status in ('unresolved','scheme_verified','patient_verified','split_verified','credit','zero_balance')),
  balance_snapshot numeric(14,2),
  owner_user_id uuid references auth.users(id) on delete set null,
  next_action_at timestamptz,
  suppress_automation boolean not null default true,
  suppression_reason text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists revenue_collection_case_queue_idx on public.revenue_collection_case(practice_id,case_status,next_action_at);
create index if not exists revenue_collection_case_owner_idx on public.revenue_collection_case(owner_user_id,case_status) where owner_user_id is not null;
create index if not exists revenue_collection_case_patient_idx on public.revenue_collection_case(patient_id,created_at desc) where patient_id is not null;
create index if not exists revenue_collection_case_snapshot_idx on public.revenue_collection_case(revenue_snapshot_id) where revenue_snapshot_id is not null;
create index if not exists revenue_collection_case_created_by_idx on public.revenue_collection_case(created_by) where created_by is not null;

alter table public.vericlaim_report_profile enable row level security;
alter table public.vericlaim_import_batch enable row level security;
alter table public.vericlaim_age_analysis_staging enable row level security;
alter table public.vericlaim_invoice_activity_staging enable row level security;
alter table public.vericlaim_scheme_claims_staging enable row level security;
alter table public.vericlaim_funder_receipts_staging enable row level security;
alter table public.vericlaim_scheme_population_staging enable row level security;
alter table public.revenue_account_snapshot enable row level security;
alter table public.revenue_collection_case enable row level security;

revoke all on table public.vericlaim_report_profile from anon,authenticated;
revoke all on table public.vericlaim_import_batch from anon,authenticated;
revoke all on table public.vericlaim_age_analysis_staging from anon,authenticated;
revoke all on table public.vericlaim_invoice_activity_staging from anon,authenticated;
revoke all on table public.vericlaim_scheme_claims_staging from anon,authenticated;
revoke all on table public.vericlaim_funder_receipts_staging from anon,authenticated;
revoke all on table public.vericlaim_scheme_population_staging from anon,authenticated;
revoke all on table public.revenue_account_snapshot from anon,authenticated;
revoke all on table public.revenue_collection_case from anon,authenticated;

grant select on table public.vericlaim_report_profile to authenticated;
grant select on table public.vericlaim_import_batch to authenticated;
grant select on table public.revenue_account_snapshot to authenticated;
grant select,insert,update on table public.revenue_collection_case to authenticated;

create policy vericlaim_profile_staff_read on public.vericlaim_report_profile for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active));
create policy vericlaim_import_privileged_read on public.vericlaim_import_batch for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=vericlaim_import_batch.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));

create policy vericlaim_age_staging_deny_client on public.vericlaim_age_analysis_staging for all to anon,authenticated using(false) with check(false);
create policy vericlaim_invoice_staging_deny_client on public.vericlaim_invoice_activity_staging for all to anon,authenticated using(false) with check(false);
create policy vericlaim_claims_staging_deny_client on public.vericlaim_scheme_claims_staging for all to anon,authenticated using(false) with check(false);
create policy vericlaim_receipts_staging_deny_client on public.vericlaim_funder_receipts_staging for all to anon,authenticated using(false) with check(false);
create policy vericlaim_population_staging_deny_client on public.vericlaim_scheme_population_staging for all to anon,authenticated using(false) with check(false);

create policy revenue_snapshot_finance_read on public.revenue_account_snapshot for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=revenue_account_snapshot.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));
create policy revenue_case_finance_read on public.revenue_collection_case for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=revenue_collection_case.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));
create policy revenue_case_finance_insert on public.revenue_collection_case for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid()) and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=revenue_collection_case.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')));
create policy revenue_case_finance_update on public.revenue_collection_case for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=revenue_collection_case.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=revenue_collection_case.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')));

commit;
