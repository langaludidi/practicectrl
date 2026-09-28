
begin;

create table if not exists public.billing_invoice_event (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoice(id) on delete restrict,
  event_type text not null check (event_type in ('created','line_added','line_removed','validated','finalised','payment_allocated','adjusted','credit_note','voided','statement_generated','other')),
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists billing_invoice_event_invoice_idx on public.billing_invoice_event(invoice_id,created_at desc);
create index if not exists billing_invoice_event_actor_idx on public.billing_invoice_event(actor_user_id) where actor_user_id is not null;

create table if not exists public.billing_validation_event (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoice(id) on delete cascade,
  invoice_line_id uuid references public.billing_invoice_line(id) on delete cascade,
  rule_code text not null,
  severity text not null check (severity in ('info','warning','blocking')),
  message text not null,
  source text not null,
  status text not null default 'open' check (status in ('open','acknowledged','resolved','overridden')),
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution_note text
);
create index if not exists billing_validation_invoice_idx on public.billing_validation_event(invoice_id,status,severity);
create index if not exists billing_validation_line_idx on public.billing_validation_event(invoice_line_id) where invoice_line_id is not null;
create index if not exists billing_validation_actor_idx on public.billing_validation_event(actor_user_id) where actor_user_id is not null;

create table if not exists public.billing_payment_receipt (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  payer_type text not null check (payer_type in ('patient','scheme','insurer','other')),
  receipt_number text not null,
  receipt_date date not null,
  amount numeric(14,2) not null check (amount <> 0),
  payment_method text,
  external_reference text,
  source_system text not null default 'PracticeCtrl',
  source_import_batch_id uuid references public.vericlaim_import_batch(id) on delete restrict,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(practice_id,source_system,receipt_number)
);
create index if not exists billing_receipt_practice_idx on public.billing_payment_receipt(practice_id,receipt_date desc);
create index if not exists billing_receipt_patient_idx on public.billing_payment_receipt(patient_id,receipt_date desc) where patient_id is not null;
create index if not exists billing_receipt_scheme_idx on public.billing_payment_receipt(medical_scheme_id,receipt_date desc) where medical_scheme_id is not null;
create index if not exists billing_receipt_import_idx on public.billing_payment_receipt(source_import_batch_id) where source_import_batch_id is not null;
create index if not exists billing_receipt_created_by_idx on public.billing_payment_receipt(created_by) where created_by is not null;

create table if not exists public.billing_payment_allocation (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.billing_payment_receipt(id) on delete restrict,
  invoice_id uuid not null references public.billing_invoice(id) on delete restrict,
  claim_id uuid references public.claim_record(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  allocation_status text not null default 'posted' check (allocation_status in ('proposed','posted','reversed')),
  allocated_by uuid references auth.users(id) on delete set null,
  allocated_at timestamptz not null default now(),
  notes text
);
create index if not exists billing_allocation_receipt_idx on public.billing_payment_allocation(receipt_id,allocation_status);
create index if not exists billing_allocation_invoice_idx on public.billing_payment_allocation(invoice_id,allocation_status);
create index if not exists billing_allocation_claim_idx on public.billing_payment_allocation(claim_id) where claim_id is not null;
create index if not exists billing_allocation_user_idx on public.billing_payment_allocation(allocated_by) where allocated_by is not null;

create table if not exists public.billing_invoice_adjustment (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.billing_invoice(id) on delete restrict,
  adjustment_type text not null check (adjustment_type in ('journal','discount','write_off','credit','reversal','correction','other')),
  amount numeric(14,2) not null check (amount <> 0),
  reason text not null,
  source_system text not null default 'PracticeCtrl',
  external_reference text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists billing_adjustment_invoice_idx on public.billing_invoice_adjustment(invoice_id,created_at desc);
create index if not exists billing_adjustment_created_by_idx on public.billing_invoice_adjustment(created_by) where created_by is not null;

alter table public.billing_invoice_event enable row level security;
alter table public.billing_validation_event enable row level security;
alter table public.billing_payment_receipt enable row level security;
alter table public.billing_payment_allocation enable row level security;
alter table public.billing_invoice_adjustment enable row level security;

revoke all on table public.billing_invoice_event from anon,authenticated;
revoke all on table public.billing_validation_event from anon,authenticated;
revoke all on table public.billing_payment_receipt from anon,authenticated;
revoke all on table public.billing_payment_allocation from anon,authenticated;
revoke all on table public.billing_invoice_adjustment from anon,authenticated;

grant select,insert on table public.billing_invoice_event to authenticated;
grant select,insert,update on table public.billing_validation_event to authenticated;
grant select,insert on table public.billing_payment_receipt to authenticated;
grant select,insert,update on table public.billing_payment_allocation to authenticated;
grant select,insert on table public.billing_invoice_adjustment to authenticated;

create policy billing_invoice_event_finance_read on public.billing_invoice_event for select to authenticated
using (exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));
create policy billing_invoice_event_finance_insert on public.billing_invoice_event for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and (actor_user_id is null or actor_user_id=(select auth.uid())) and exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));

create policy billing_validation_finance_read on public.billing_validation_event for select to authenticated
using (exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_validation_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));
create policy billing_validation_finance_write on public.billing_validation_event for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_validation_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_validation_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));

create policy billing_receipt_finance_read on public.billing_payment_receipt for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_payment_receipt.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));
create policy billing_receipt_finance_insert on public.billing_payment_receipt for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and (created_by is null or created_by=(select auth.uid())) and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_payment_receipt.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')));

create policy billing_allocation_finance_read on public.billing_payment_allocation for select to authenticated
using (exists (select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));
create policy billing_allocation_finance_write on public.billing_payment_allocation for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));

create policy billing_adjustment_finance_read on public.billing_invoice_adjustment for select to authenticated
using (exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_adjustment.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor')));
create policy billing_adjustment_finance_insert on public.billing_invoice_adjustment for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid()) and exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_adjustment.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));

commit;
