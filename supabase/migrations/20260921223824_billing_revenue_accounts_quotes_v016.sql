create table public.practice_billing_profile (
  practice_id uuid primary key references public.practice(id) on delete cascade,
  legal_name text,
  trading_name text,
  registration_number text,
  vat_registered boolean not null default false,
  vat_registration_number text,
  default_tax_rate numeric(7,6) not null default 0.15 check (default_tax_rate>=0 and default_tax_rate<=1),
  address jsonb not null default '{}'::jsonb,
  email text,
  phone text,
  banking_details jsonb not null default '{}'::jsonb,
  payment_terms_days integer not null default 30 check (payment_terms_days between 0 and 365),
  invoice_footer text,
  quote_footer text,
  statement_footer text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint practice_billing_profile_vat_ck check (
    not vat_registered or nullif(trim(coalesce(vat_registration_number,'')),'') is not null
  )
);

create table public.billing_account (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  account_number text not null,
  account_type text not null check (account_type in ('patient','responsible_person','medical_scheme','insurer','employer','attorney','corporate','other')),
  patient_id uuid references public.crm_patient(id) on delete restrict,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  display_name text not null,
  legal_name text,
  contact_name text,
  email text,
  phone text,
  billing_address jsonb not null default '{}'::jsonb,
  vat_registration_number text,
  payment_terms_days integer not null default 30 check (payment_terms_days between 0 and 365),
  credit_limit numeric(14,2),
  status text not null default 'active' check (status in ('active','on_hold','closed')),
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(practice_id,account_number)
);
create unique index billing_account_patient_uq on public.billing_account(practice_id,patient_id)
  where account_type='patient' and patient_id is not null;
create unique index billing_account_scheme_uq on public.billing_account(practice_id,medical_scheme_id)
  where account_type='medical_scheme' and medical_scheme_id is not null;
create index billing_account_practice_type_idx on public.billing_account(practice_id,account_type,status);
create index billing_account_patient_idx on public.billing_account(patient_id) where patient_id is not null;
create index billing_account_scheme_idx on public.billing_account(medical_scheme_id) where medical_scheme_id is not null;
create index billing_account_created_by_idx on public.billing_account(created_by) where created_by is not null;
create index billing_account_updated_by_idx on public.billing_account(updated_by) where updated_by is not null;

create table public.billing_document_sequence (
  practice_id uuid not null references public.practice(id) on delete cascade,
  document_type text not null check (document_type in ('invoice','quote','credit_note','receipt','statement')),
  prefix text not null,
  next_value bigint not null default 1 check (next_value>0),
  padding integer not null default 6 check (padding between 3 and 12),
  include_year boolean not null default true,
  annual_reset boolean not null default true,
  current_year integer not null default extract(year from current_date)::integer,
  updated_at timestamptz not null default now(),
  primary key(practice_id,document_type)
);

create table public.billing_quote (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  account_id uuid not null references public.billing_account(id) on delete restrict,
  patient_id uuid references public.crm_patient(id) on delete restrict,
  encounter_id uuid references public.practice_encounter(id) on delete restrict,
  quote_number text not null,
  quote_date date not null default current_date,
  valid_until date,
  status text not null default 'draft' check (status in ('draft','sent','accepted','rejected','expired','converted','void')),
  currency char(3) not null default 'ZAR',
  subtotal_amount numeric(14,2) not null default 0 check (subtotal_amount>=0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount>=0),
  total_amount numeric(14,2) not null default 0 check (total_amount>=0),
  reference text,
  notes text,
  terms text,
  supplier_snapshot jsonb not null default '{}'::jsonb,
  recipient_snapshot jsonb not null default '{}'::jsonb,
  converted_invoice_id uuid,
  created_by uuid references auth.users(id) on delete set null,
  sent_at timestamptz,
  accepted_at timestamptz,
  rejected_at timestamptz,
  converted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(practice_id,quote_number),
  constraint billing_quote_validity_ck check (valid_until is null or valid_until>=quote_date)
);
create index billing_quote_account_idx on public.billing_quote(account_id,quote_date desc);
create index billing_quote_patient_idx on public.billing_quote(patient_id) where patient_id is not null;
create index billing_quote_encounter_idx on public.billing_quote(encounter_id) where encounter_id is not null;
create index billing_quote_created_by_idx on public.billing_quote(created_by) where created_by is not null;

create table public.billing_quote_line (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.billing_quote(id) on delete cascade,
  line_no integer not null check (line_no>0),
  line_type text not null default 'transactional' check (line_type in ('clinical','transactional')),
  code_system text references public.billing_code_system(code) on delete restrict,
  code text,
  description text not null,
  modifier_codes text[] not null default '{}',
  diagnosis_codes text[] not null default '{}',
  quantity numeric(14,4) not null default 1 check (quantity>0),
  unit_amount numeric(14,2) not null check (unit_amount>=0),
  tax_rate numeric(7,6) not null default 0 check (tax_rate>=0 and tax_rate<=1),
  tax_amount numeric(14,2) not null default 0 check (tax_amount>=0),
  line_amount numeric(14,2) not null check (line_amount>=0),
  claim_eligible boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(quote_id,line_no)
);
create index billing_quote_line_quote_idx on public.billing_quote_line(quote_id,line_no);

create table public.billing_quote_event (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.billing_quote(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index billing_quote_event_quote_idx on public.billing_quote_event(quote_id,created_at desc);
create index billing_quote_event_actor_idx on public.billing_quote_event(actor_user_id) where actor_user_id is not null;

alter table public.practice_billing_profile enable row level security;
alter table public.billing_account enable row level security;
alter table public.billing_document_sequence enable row level security;
alter table public.billing_quote enable row level security;
alter table public.billing_quote_line enable row level security;
alter table public.billing_quote_event enable row level security;

revoke all on public.practice_billing_profile,public.billing_account,public.billing_document_sequence,public.billing_quote,public.billing_quote_line,public.billing_quote_event from anon,authenticated;
grant select,insert,update on public.practice_billing_profile to authenticated;
grant select,insert,update on public.billing_account to authenticated;
grant select on public.billing_document_sequence to authenticated;
grant select,insert,update on public.billing_quote to authenticated;
grant select,insert,update,delete on public.billing_quote_line to authenticated;
grant select,insert on public.billing_quote_event to authenticated;

create policy practice_billing_profile_read on public.practice_billing_profile for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice_billing_profile.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy practice_billing_profile_manage on public.practice_billing_profile for all to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice_billing_profile.practice_id and m.active and m.role in ('practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice_billing_profile.practice_id and m.active and m.role in ('practice_manager','system_admin'))
);

create policy billing_account_read on public.billing_account for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_account_manage on public.billing_account for all to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create policy billing_document_sequence_read on public.billing_document_sequence for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_document_sequence.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);

create policy billing_quote_read on public.billing_quote for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_quote_manage on public.billing_quote for all to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create policy billing_quote_line_read on public.billing_quote_line for select to authenticated using (
  exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_line.quote_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_quote_line_manage on public.billing_quote_line for all to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create policy billing_quote_event_read on public.billing_quote_event for select to authenticated using (
  exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_event.quote_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_quote_event_insert on public.billing_quote_event for insert to authenticated with check (
  actor_user_id=(select auth.uid())
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_event.quote_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create trigger tenant_guard_billing_account_patient before insert or update of practice_id,patient_id on public.billing_account
for each row when (new.patient_id is not null) execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger tenant_guard_billing_quote_account before insert or update of practice_id,account_id on public.billing_quote
for each row execute function public.enforce_same_practice_reference('billing_account','account_id');
create trigger tenant_guard_billing_quote_patient before insert or update of practice_id,patient_id on public.billing_quote
for each row when (new.patient_id is not null) execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger tenant_guard_billing_quote_encounter before insert or update of practice_id,encounter_id on public.billing_quote
for each row when (new.encounter_id is not null) execute function public.enforce_same_practice_reference('practice_encounter','encounter_id');
