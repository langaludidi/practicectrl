
begin;

create table if not exists public.source_dataset_release (
  id uuid primary key default gen_random_uuid(),
  dataset_id uuid not null references public.source_dataset(id) on delete restrict,
  release_name text not null,
  version text,
  published_date date,
  effective_from date,
  effective_to date,
  retrieved_at timestamptz not null default now(),
  source_uri text,
  content_sha256 text,
  licence_reference text,
  status text not null default 'pending_review'
    check (status in ('pending_review','active','superseded','archived','rejected')),
  imported_by uuid references auth.users(id) on delete set null,
  activated_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  constraint source_dataset_release_hash_unique unique(dataset_id,content_sha256),
  constraint source_dataset_release_dates_ck check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);
create index if not exists source_dataset_release_dataset_idx
  on public.source_dataset_release(dataset_id,status,effective_from);

create table if not exists public.billing_code_system (
  code text primary key,
  display_name text not null,
  code_domain text not null check (code_domain in ('diagnosis','procedure','product','modifier','other')),
  owner_provider_id uuid references public.integration_provider(id) on delete restrict,
  licence_required boolean not null default false,
  notes text
);

create table if not exists public.billing_code_reference (
  id uuid primary key default gen_random_uuid(),
  code_system text not null references public.billing_code_system(code) on delete restrict,
  code text not null,
  description text not null,
  source_release_id uuid references public.source_dataset_release(id) on delete restrict,
  effective_from date,
  effective_to date,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint billing_code_reference_unique unique(code_system,code,source_release_id),
  constraint billing_code_reference_dates_ck check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);
create index if not exists billing_code_reference_lookup_idx
  on public.billing_code_reference(code_system,code,active);

create table if not exists public.tariff_schedule (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  practice_id uuid references public.practice(id) on delete cascade,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  medical_scheme_option_id uuid references public.medical_scheme_option(id) on delete restrict,
  discipline_code text,
  contract_reference text,
  rate_basis text not null
    check (rate_basis in ('scheme_rate','contract_rate','practice_rate','reference_rate')),
  source_release_id uuid references public.source_dataset_release(id) on delete restrict,
  effective_from date not null,
  effective_to date,
  currency char(3) not null default 'ZAR',
  status text not null default 'draft'
    check (status in ('draft','active','superseded','archived')),
  created_at timestamptz not null default now(),
  constraint tariff_schedule_dates_ck check (effective_to is null or effective_to >= effective_from)
);
create index if not exists tariff_schedule_lookup_idx
  on public.tariff_schedule(medical_scheme_id,medical_scheme_option_id,practice_id,effective_from,effective_to);

create table if not exists public.tariff_rate (
  id uuid primary key default gen_random_uuid(),
  tariff_schedule_id uuid not null references public.tariff_schedule(id) on delete restrict,
  code_system text not null references public.billing_code_system(code) on delete restrict,
  code text not null,
  modifier text,
  unit_basis text,
  unit_value numeric(14,4),
  amount numeric(14,2),
  rule_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint tariff_rate_nonnegative_ck check (
    (amount is null or amount >= 0) and (unit_value is null or unit_value >= 0)
  )
);
create index if not exists tariff_rate_lookup_idx
  on public.tariff_rate(tariff_schedule_id,code_system,code,modifier);

create table if not exists public.billing_invoice (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid,
  encounter_id uuid,
  invoice_number text not null,
  invoice_date date not null,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  medical_scheme_option_id uuid references public.medical_scheme_option(id) on delete restrict,
  status text not null default 'draft'
    check (status in ('draft','final','part_paid','paid','outstanding','void')),
  total_amount numeric(14,2) not null default 0,
  scheme_portion numeric(14,2) not null default 0,
  patient_portion numeric(14,2) not null default 0,
  received_amount numeric(14,2) not null default 0,
  balance_amount numeric(14,2) not null default 0,
  source_system text not null default 'PracticeCtrl',
  created_by uuid references auth.users(id) on delete set null,
  finalised_by uuid references auth.users(id) on delete set null,
  finalised_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint billing_invoice_number_unique unique(practice_id,invoice_number)
);
create index if not exists billing_invoice_practice_date_idx
  on public.billing_invoice(practice_id,invoice_date desc);
create index if not exists billing_invoice_patient_idx
  on public.billing_invoice(patient_id) where patient_id is not null;

create table if not exists public.billing_invoice_line (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoice(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  code_system text not null references public.billing_code_system(code) on delete restrict,
  code text not null,
  description_snapshot text not null,
  modifier_codes text[] not null default '{}',
  diagnosis_codes text[] not null default '{}',
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  unit_amount numeric(14,2) not null check (unit_amount >= 0),
  line_amount numeric(14,2) not null check (line_amount >= 0),
  tariff_rate_id uuid references public.tariff_rate(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(invoice_id,line_no)
);

create table if not exists public.claim_record (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  invoice_id uuid references public.billing_invoice(id) on delete restrict,
  patient_id uuid,
  encounter_id uuid,
  medical_scheme_id uuid not null references public.medical_scheme(id) on delete restrict,
  medical_scheme_option_id uuid references public.medical_scheme_option(id) on delete restrict,
  claim_status text not null default 'draft'
    check (claim_status in (
      'draft','validated','submitted','accepted','partially_accepted','rejected',
      'paid','part_paid','reversed','cancelled','exception'
    )),
  service_from date not null,
  service_to date,
  total_claimed numeric(14,2) not null default 0,
  total_accepted numeric(14,2),
  total_paid numeric(14,2),
  patient_liability numeric(14,2),
  latest_tracking_number text,
  submitted_at timestamptz,
  latest_response_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint claim_record_dates_ck check (service_to is null or service_to >= service_from)
);
create index if not exists claim_record_practice_status_idx
  on public.claim_record(practice_id,claim_status,service_from desc);
create index if not exists claim_record_invoice_idx
  on public.claim_record(invoice_id) where invoice_id is not null;

create table if not exists public.claim_line (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references public.claim_record(id) on delete restrict,
  invoice_line_id uuid references public.billing_invoice_line(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  code_system text not null references public.billing_code_system(code) on delete restrict,
  code text not null,
  modifier_codes text[] not null default '{}',
  diagnosis_codes text[] not null default '{}',
  quantity numeric(12,3) not null default 1 check (quantity > 0),
  claimed_amount numeric(14,2) not null check (claimed_amount >= 0),
  accepted_amount numeric(14,2),
  paid_amount numeric(14,2),
  patient_liability numeric(14,2),
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  unique(claim_id,line_no)
);

create table if not exists public.payer_transaction (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  capability_code text not null references public.integration_capability_catalog(code) on delete restrict,
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  interface_id uuid references public.integration_interface(id) on delete restrict,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  medical_scheme_option_id uuid references public.medical_scheme_option(id) on delete restrict,
  patient_id uuid,
  encounter_id uuid,
  claim_id uuid references public.claim_record(id) on delete restrict,
  request_id uuid not null default gen_random_uuid(),
  external_transaction_ref text,
  transaction_status text not null default 'created'
    check (transaction_status in ('created','queued','sent','acknowledged','completed','failed','timed_out','cancelled')),
  request_sha256 text,
  request_payload_ref text,
  response_payload_ref text,
  response_code text,
  response_summary text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  latency_ms integer,
  created_by uuid references auth.users(id) on delete set null,
  constraint payer_transaction_latency_ck check (latency_ms is null or latency_ms >= 0)
);
create index if not exists payer_transaction_practice_time_idx
  on public.payer_transaction(practice_id,started_at desc);
create index if not exists payer_transaction_claim_idx
  on public.payer_transaction(claim_id) where claim_id is not null;
create unique index if not exists payer_transaction_request_id_idx
  on public.payer_transaction(request_id);

create table if not exists public.claim_response_message (
  id uuid primary key default gen_random_uuid(),
  payer_transaction_id uuid not null references public.payer_transaction(id) on delete restrict,
  claim_id uuid references public.claim_record(id) on delete restrict,
  claim_line_id uuid references public.claim_line(id) on delete restrict,
  message_code text,
  severity text not null default 'info'
    check (severity in ('info','warning','rejection','error')),
  message text not null,
  source text,
  created_at timestamptz not null default now()
);
create index if not exists claim_response_message_tx_idx
  on public.claim_response_message(payer_transaction_id);

create table if not exists public.remittance_advice (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  interface_id uuid references public.integration_interface(id) on delete restrict,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  external_era_ref text,
  payment_date date,
  payment_reference_masked text,
  total_amount numeric(14,2) not null default 0,
  currency char(3) not null default 'ZAR',
  source_payload_ref text,
  content_sha256 text,
  status text not null default 'received'
    check (status in ('received','parsed','partially_matched','matched','reconciled','exception')),
  received_at timestamptz not null default now(),
  reconciled_at timestamptz,
  reconciled_by uuid references auth.users(id) on delete set null,
  unique(practice_id,provider_id,external_era_ref)
);
create index if not exists remittance_advice_practice_date_idx
  on public.remittance_advice(practice_id,payment_date desc,received_at desc);

create table if not exists public.remittance_line (
  id uuid primary key default gen_random_uuid(),
  remittance_id uuid not null references public.remittance_advice(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  external_claim_ref text,
  claim_id uuid references public.claim_record(id) on delete restrict,
  claim_line_id uuid references public.claim_line(id) on delete restrict,
  service_date date,
  code text,
  claimed_amount numeric(14,2),
  accepted_amount numeric(14,2),
  paid_amount numeric(14,2),
  patient_liability numeric(14,2),
  adjustment_amount numeric(14,2),
  reason_code text,
  reason_text text,
  raw_line_ref text,
  created_at timestamptz not null default now(),
  unique(remittance_id,line_no)
);
create index if not exists remittance_line_claim_idx
  on public.remittance_line(claim_id) where claim_id is not null;

create table if not exists public.remittance_match (
  id uuid primary key default gen_random_uuid(),
  remittance_line_id uuid not null references public.remittance_line(id) on delete restrict,
  claim_id uuid references public.claim_record(id) on delete restrict,
  claim_line_id uuid references public.claim_line(id) on delete restrict,
  match_status text not null
    check (match_status in ('auto_exact','auto_probable','manual','unmatched','rejected')),
  match_method text,
  matched_by uuid references auth.users(id) on delete set null,
  matched_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists remittance_match_line_idx
  on public.remittance_match(remittance_line_id,match_status);

-- Enable RLS.
alter table public.source_dataset_release enable row level security;
alter table public.billing_code_system enable row level security;
alter table public.billing_code_reference enable row level security;
alter table public.tariff_schedule enable row level security;
alter table public.tariff_rate enable row level security;
alter table public.billing_invoice enable row level security;
alter table public.billing_invoice_line enable row level security;
alter table public.claim_record enable row level security;
alter table public.claim_line enable row level security;
alter table public.payer_transaction enable row level security;
alter table public.claim_response_message enable row level security;
alter table public.remittance_advice enable row level security;
alter table public.remittance_line enable row level security;
alter table public.remittance_match enable row level security;

-- Global governed reference data: staff-readable only.
revoke all on table public.source_dataset_release from anon, authenticated;
revoke all on table public.billing_code_system from anon, authenticated;
revoke all on table public.billing_code_reference from anon, authenticated;
revoke all on table public.tariff_schedule from anon, authenticated;
revoke all on table public.tariff_rate from anon, authenticated;
grant select on table public.source_dataset_release to authenticated;
grant select on table public.billing_code_system to authenticated;
grant select on table public.billing_code_reference to authenticated;
grant select on table public.tariff_schedule to authenticated;
grant select on table public.tariff_rate to authenticated;

create policy source_dataset_release_staff_read on public.source_dataset_release
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active
));
create policy billing_code_system_staff_read on public.billing_code_system
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active
));
create policy billing_code_reference_staff_read on public.billing_code_reference
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active
));
create policy tariff_schedule_staff_read on public.tariff_schedule
for select to authenticated using (
  practice_id is null or exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=tariff_schedule.practice_id and m.active
  )
);
create policy tariff_rate_staff_read on public.tariff_rate
for select to authenticated using (exists (
  select 1 from public.tariff_schedule s
  where s.id=tariff_rate.tariff_schedule_id
    and (s.practice_id is null or exists (
      select 1 from public.practice_staff_member m
      where m.user_id=(select auth.uid()) and m.practice_id=s.practice_id and m.active
    ))
));

-- Tenant financial/claims data. Read limited to finance/management/audit.
revoke all on table public.billing_invoice from anon, authenticated;
revoke all on table public.billing_invoice_line from anon, authenticated;
revoke all on table public.claim_record from anon, authenticated;
revoke all on table public.claim_line from anon, authenticated;
revoke all on table public.payer_transaction from anon, authenticated;
revoke all on table public.claim_response_message from anon, authenticated;
revoke all on table public.remittance_advice from anon, authenticated;
revoke all on table public.remittance_line from anon, authenticated;
revoke all on table public.remittance_match from anon, authenticated;

grant select,insert on table public.billing_invoice to authenticated;
grant update (status,total_amount,scheme_portion,patient_portion,received_amount,balance_amount,finalised_by,finalised_at,updated_at)
  on table public.billing_invoice to authenticated;
grant select,insert on table public.billing_invoice_line to authenticated;

grant select,insert on table public.claim_record to authenticated;
grant update (claim_status,total_claimed,total_accepted,total_paid,patient_liability,latest_tracking_number,submitted_at,latest_response_at,updated_at)
  on table public.claim_record to authenticated;
grant select,insert on table public.claim_line to authenticated;
grant update (accepted_amount,paid_amount,patient_liability,status)
  on table public.claim_line to authenticated;

grant select,insert on table public.payer_transaction to authenticated;
grant update (external_transaction_ref,transaction_status,response_payload_ref,response_code,response_summary,completed_at,latency_ms)
  on table public.payer_transaction to authenticated;
grant select,insert on table public.claim_response_message to authenticated;

grant select,insert on table public.remittance_advice to authenticated;
grant update (status,reconciled_at,reconciled_by)
  on table public.remittance_advice to authenticated;
grant select,insert on table public.remittance_line to authenticated;
grant update (claim_id,claim_line_id) on table public.remittance_line to authenticated;
grant select,insert on table public.remittance_match to authenticated;

create policy billing_invoice_finance_read on public.billing_invoice
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=billing_invoice.practice_id and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy billing_invoice_finance_insert on public.billing_invoice
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);
create policy billing_invoice_finance_update on public.billing_invoice
for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

create policy billing_invoice_line_finance_read on public.billing_invoice_line
for select to authenticated using (exists (
  select 1 from public.billing_invoice i
  join public.practice_staff_member m on m.practice_id=i.practice_id
  where i.id=billing_invoice_line.invoice_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy billing_invoice_line_finance_insert on public.billing_invoice_line
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.billing_invoice i
    join public.practice_staff_member m on m.practice_id=i.practice_id
    where i.id=billing_invoice_line.invoice_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
      and i.status='draft'
  )
);

create policy claim_record_finance_read on public.claim_record
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=claim_record.practice_id and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy claim_record_finance_insert on public.claim_record
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=claim_record.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);
create policy claim_record_finance_update on public.claim_record
for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=claim_record.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=claim_record.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

create policy claim_line_finance_read on public.claim_line
for select to authenticated using (exists (
  select 1 from public.claim_record c
  join public.practice_staff_member m on m.practice_id=c.practice_id
  where c.id=claim_line.claim_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy claim_line_finance_insert on public.claim_line
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.claim_record c
    join public.practice_staff_member m on m.practice_id=c.practice_id
    where c.id=claim_line.claim_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
      and c.claim_status='draft'
  )
);
create policy claim_line_finance_update on public.claim_line
for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.claim_record c
    join public.practice_staff_member m on m.practice_id=c.practice_id
    where c.id=claim_line.claim_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.claim_record c
    join public.practice_staff_member m on m.practice_id=c.practice_id
    where c.id=claim_line.claim_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

create policy payer_transaction_finance_read on public.payer_transaction
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=payer_transaction.practice_id and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy payer_transaction_finance_insert on public.payer_transaction
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=payer_transaction.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);
create policy payer_transaction_finance_update on public.payer_transaction
for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=payer_transaction.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=payer_transaction.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

create policy claim_response_message_finance_read on public.claim_response_message
for select to authenticated using (exists (
  select 1 from public.payer_transaction t
  join public.practice_staff_member m on m.practice_id=t.practice_id
  where t.id=claim_response_message.payer_transaction_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy claim_response_message_finance_insert on public.claim_response_message
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.payer_transaction t
    join public.practice_staff_member m on m.practice_id=t.practice_id
    where t.id=claim_response_message.payer_transaction_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

create policy remittance_advice_finance_read on public.remittance_advice
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=remittance_advice.practice_id and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy remittance_advice_finance_insert on public.remittance_advice
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=remittance_advice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);
create policy remittance_advice_finance_update on public.remittance_advice
for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=remittance_advice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=remittance_advice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

create policy remittance_line_finance_read on public.remittance_line
for select to authenticated using (exists (
  select 1 from public.remittance_advice r
  join public.practice_staff_member m on m.practice_id=r.practice_id
  where r.id=remittance_line.remittance_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy remittance_line_finance_insert on public.remittance_line
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.remittance_advice r
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=remittance_line.remittance_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);
create policy remittance_line_finance_update on public.remittance_line
for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.remittance_advice r
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=remittance_line.remittance_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.remittance_advice r
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=remittance_line.remittance_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

create policy remittance_match_finance_read on public.remittance_match
for select to authenticated using (exists (
  select 1 from public.remittance_line l
  join public.remittance_advice r on r.id=l.remittance_id
  join public.practice_staff_member m on m.practice_id=r.practice_id
  where l.id=remittance_match.remittance_line_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy remittance_match_finance_insert on public.remittance_match
for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.remittance_line l
    join public.remittance_advice r on r.id=l.remittance_id
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where l.id=remittance_match.remittance_line_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

commit;
