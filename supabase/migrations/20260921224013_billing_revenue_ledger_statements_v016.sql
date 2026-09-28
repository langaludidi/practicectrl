alter table public.billing_invoice
  add column account_id uuid references public.billing_account(id) on delete restrict,
  add column quote_id uuid references public.billing_quote(id) on delete restrict,
  add column invoice_kind text not null default 'transactional' check (invoice_kind in ('clinical','transactional','mixed')),
  add column due_date date,
  add column currency char(3) not null default 'ZAR',
  add column subtotal_amount numeric(14,2) not null default 0 check (subtotal_amount>=0),
  add column tax_amount numeric(14,2) not null default 0 check (tax_amount>=0),
  add column credited_amount numeric(14,2) not null default 0 check (credited_amount>=0),
  add column reference text,
  add column notes text,
  add column terms text,
  add column tax_invoice boolean not null default false,
  add column supplier_snapshot jsonb not null default '{}'::jsonb,
  add column recipient_snapshot jsonb not null default '{}'::jsonb;

create index billing_invoice_account_idx on public.billing_invoice(account_id,invoice_date desc) where account_id is not null;
create index billing_invoice_quote_idx on public.billing_invoice(quote_id) where quote_id is not null;
create index billing_invoice_due_idx on public.billing_invoice(practice_id,due_date,status) where due_date is not null;

alter table public.billing_quote
  add constraint billing_quote_converted_invoice_fkey
  foreign key (converted_invoice_id) references public.billing_invoice(id) on delete restrict;

alter table public.billing_invoice_line
  add column line_type text not null default 'transactional' check (line_type in ('clinical','transactional')),
  add column service_date date,
  add column tax_rate numeric(7,6) not null default 0 check (tax_rate>=0 and tax_rate<=1),
  add column tax_amount numeric(14,2) not null default 0 check (tax_amount>=0),
  add column patient_portion numeric(14,2) not null default 0 check (patient_portion>=0),
  add column scheme_portion numeric(14,2) not null default 0 check (scheme_portion>=0),
  add column claim_eligible boolean not null default false;

update public.billing_invoice_line
set claim_eligible=coalesce((metadata->>'claim_eligible')::boolean,false),
    patient_portion=line_amount,
    scheme_portion=0
where true;

update public.billing_invoice
set subtotal_amount=total_amount,
    due_date=coalesce(due_date,invoice_date+30)
where true;

alter table public.billing_payment_receipt
  add column account_id uuid references public.billing_account(id) on delete restrict;
create index billing_receipt_account_idx on public.billing_payment_receipt(account_id,receipt_date desc) where account_id is not null;

create table public.billing_invoice_liability (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  invoice_id uuid not null references public.billing_invoice(id) on delete cascade,
  account_id uuid not null references public.billing_account(id) on delete restrict,
  liability_type text not null check (liability_type in ('patient','scheme','other')),
  amount numeric(14,2) not null check (amount>=0),
  created_at timestamptz not null default now(),
  unique(invoice_id,account_id,liability_type)
);
create index billing_invoice_liability_account_idx on public.billing_invoice_liability(account_id,invoice_id);
create index billing_invoice_liability_invoice_idx on public.billing_invoice_liability(invoice_id);

create table public.billing_credit_note (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  account_id uuid not null references public.billing_account(id) on delete restrict,
  invoice_id uuid not null references public.billing_invoice(id) on delete restrict,
  credit_note_number text not null,
  credit_note_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft','final','void')),
  currency char(3) not null default 'ZAR',
  subtotal_amount numeric(14,2) not null default 0 check (subtotal_amount>=0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount>=0),
  total_amount numeric(14,2) not null default 0 check (total_amount>0),
  reason text not null,
  supplier_snapshot jsonb not null default '{}'::jsonb,
  recipient_snapshot jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  finalised_by uuid references auth.users(id) on delete set null,
  finalised_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(practice_id,credit_note_number)
);
create index billing_credit_note_account_idx on public.billing_credit_note(account_id,credit_note_date desc);
create index billing_credit_note_invoice_idx on public.billing_credit_note(invoice_id,credit_note_date desc);
create index billing_credit_note_created_by_idx on public.billing_credit_note(created_by) where created_by is not null;
create index billing_credit_note_finalised_by_idx on public.billing_credit_note(finalised_by) where finalised_by is not null;

create table public.billing_credit_note_line (
  id uuid primary key default gen_random_uuid(),
  credit_note_id uuid not null references public.billing_credit_note(id) on delete cascade,
  invoice_line_id uuid references public.billing_invoice_line(id) on delete restrict,
  line_no integer not null check (line_no>0),
  description text not null,
  quantity numeric(14,4) not null default 1 check (quantity>0),
  unit_amount numeric(14,2) not null check (unit_amount>=0),
  tax_rate numeric(7,6) not null default 0 check (tax_rate>=0 and tax_rate<=1),
  tax_amount numeric(14,2) not null default 0 check (tax_amount>=0),
  line_amount numeric(14,2) not null check (line_amount>0),
  created_at timestamptz not null default now(),
  unique(credit_note_id,line_no)
);
create index billing_credit_note_line_invoice_line_idx on public.billing_credit_note_line(invoice_line_id) where invoice_line_id is not null;

create table public.billing_credit_note_event (
  id uuid primary key default gen_random_uuid(),
  credit_note_id uuid not null references public.billing_credit_note(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index billing_credit_note_event_note_idx on public.billing_credit_note_event(credit_note_id,created_at desc);
create index billing_credit_note_event_actor_idx on public.billing_credit_note_event(actor_user_id) where actor_user_id is not null;

create table public.billing_ledger_entry (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  account_id uuid not null references public.billing_account(id) on delete restrict,
  transaction_date date not null,
  entry_type text not null check (entry_type in ('invoice','credit_note','receipt_allocation','allocation_reversal','writeoff','adjustment','opening_balance')),
  document_number text,
  description text not null,
  signed_amount numeric(14,2) not null check (signed_amount<>0),
  invoice_id uuid references public.billing_invoice(id) on delete restrict,
  credit_note_id uuid references public.billing_credit_note(id) on delete restrict,
  receipt_id uuid references public.billing_payment_receipt(id) on delete restrict,
  allocation_id uuid references public.billing_payment_allocation(id) on delete restrict,
  reversal_of_entry_id uuid references public.billing_ledger_entry(id) on delete restrict,
  source_key text not null,
  created_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(practice_id,source_key)
);
create index billing_ledger_account_date_idx on public.billing_ledger_entry(account_id,transaction_date,id);
create index billing_ledger_invoice_idx on public.billing_ledger_entry(invoice_id) where invoice_id is not null;
create index billing_ledger_credit_idx on public.billing_ledger_entry(credit_note_id) where credit_note_id is not null;
create index billing_ledger_receipt_idx on public.billing_ledger_entry(receipt_id) where receipt_id is not null;
create index billing_ledger_allocation_idx on public.billing_ledger_entry(allocation_id) where allocation_id is not null;
create index billing_ledger_created_by_idx on public.billing_ledger_entry(created_by) where created_by is not null;

create table public.billing_statement (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  account_id uuid not null references public.billing_account(id) on delete restrict,
  statement_number text not null,
  statement_date date not null default current_date,
  period_from date not null,
  period_to date not null,
  opening_balance numeric(14,2) not null default 0,
  debit_total numeric(14,2) not null default 0 check (debit_total>=0),
  credit_total numeric(14,2) not null default 0 check (credit_total>=0),
  closing_balance numeric(14,2) not null default 0,
  currency char(3) not null default 'ZAR',
  supplier_snapshot jsonb not null default '{}'::jsonb,
  recipient_snapshot jsonb not null default '{}'::jsonb,
  generated_by uuid references auth.users(id) on delete set null,
  generated_at timestamptz not null default now(),
  unique(practice_id,statement_number),
  constraint billing_statement_period_ck check (period_to>=period_from)
);
create index billing_statement_account_idx on public.billing_statement(account_id,statement_date desc);
create index billing_statement_generated_by_idx on public.billing_statement(generated_by) where generated_by is not null;

create table public.billing_statement_line (
  id uuid primary key default gen_random_uuid(),
  statement_id uuid not null references public.billing_statement(id) on delete cascade,
  line_no integer not null check (line_no>0),
  ledger_entry_id uuid not null references public.billing_ledger_entry(id) on delete restrict,
  transaction_date date not null,
  document_number text,
  description text not null,
  debit_amount numeric(14,2) not null default 0 check (debit_amount>=0),
  credit_amount numeric(14,2) not null default 0 check (credit_amount>=0),
  running_balance numeric(14,2) not null,
  unique(statement_id,line_no),
  unique(statement_id,ledger_entry_id)
);
create index billing_statement_line_ledger_idx on public.billing_statement_line(ledger_entry_id);

alter table public.billing_invoice_liability enable row level security;
alter table public.billing_credit_note enable row level security;
alter table public.billing_credit_note_line enable row level security;
alter table public.billing_credit_note_event enable row level security;
alter table public.billing_ledger_entry enable row level security;
alter table public.billing_statement enable row level security;
alter table public.billing_statement_line enable row level security;

revoke all on public.billing_invoice_liability,public.billing_credit_note,public.billing_credit_note_line,public.billing_credit_note_event,public.billing_ledger_entry,public.billing_statement,public.billing_statement_line from anon,authenticated;
grant select,insert,update,delete on public.billing_invoice_liability to authenticated;
grant select,insert,update on public.billing_credit_note to authenticated;
grant select,insert,update,delete on public.billing_credit_note_line to authenticated;
grant select,insert on public.billing_credit_note_event to authenticated;
grant select on public.billing_ledger_entry to authenticated;
grant select,insert on public.billing_statement to authenticated;
grant select,insert on public.billing_statement_line to authenticated;

create policy billing_invoice_liability_read on public.billing_invoice_liability for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_invoice_liability.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_invoice_liability_manage on public.billing_invoice_liability for all to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_liability.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_liability.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create policy billing_credit_note_read on public.billing_credit_note for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_credit_note_manage on public.billing_credit_note for all to authenticated using (
  ((select auth.jwt())->>'aal')='aal2' and status='draft'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create policy billing_credit_note_line_read on public.billing_credit_note_line for select to authenticated using (
  exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_line.credit_note_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_credit_note_line_manage on public.billing_credit_note_line for all to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create policy billing_credit_note_event_read on public.billing_credit_note_event for select to authenticated using (
  exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_event.credit_note_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_credit_note_event_insert on public.billing_credit_note_event for insert to authenticated with check (
  actor_user_id=(select auth.uid())
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_event.credit_note_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create policy billing_ledger_read on public.billing_ledger_entry for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_ledger_entry.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);

create policy billing_statement_read on public.billing_statement for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_statement.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_statement_insert on public.billing_statement for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and generated_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_statement.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_statement_line_read on public.billing_statement_line for select to authenticated using (
  exists(select 1 from public.billing_statement s join public.practice_staff_member m on m.practice_id=s.practice_id where s.id=billing_statement_line.statement_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin','auditor'))
);
create policy billing_statement_line_insert on public.billing_statement_line for insert to authenticated with check (
  exists(select 1 from public.billing_statement s join public.practice_staff_member m on m.practice_id=s.practice_id where s.id=billing_statement_line.statement_id and s.generated_by=(select auth.uid()) and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create trigger tenant_guard_invoice_account before insert or update of practice_id,account_id on public.billing_invoice
for each row when (new.account_id is not null) execute function public.enforce_same_practice_reference('billing_account','account_id');
create trigger tenant_guard_receipt_account before insert or update of practice_id,account_id on public.billing_payment_receipt
for each row when (new.account_id is not null) execute function public.enforce_same_practice_reference('billing_account','account_id');
create trigger tenant_guard_invoice_liability_invoice before insert or update of practice_id,invoice_id on public.billing_invoice_liability
for each row execute function public.enforce_same_practice_reference('billing_invoice','invoice_id');
create trigger tenant_guard_invoice_liability_account before insert or update of practice_id,account_id on public.billing_invoice_liability
for each row execute function public.enforce_same_practice_reference('billing_account','account_id');
create trigger tenant_guard_credit_account before insert or update of practice_id,account_id on public.billing_credit_note
for each row execute function public.enforce_same_practice_reference('billing_account','account_id');
create trigger tenant_guard_credit_invoice before insert or update of practice_id,invoice_id on public.billing_credit_note
for each row execute function public.enforce_same_practice_reference('billing_invoice','invoice_id');
create trigger tenant_guard_ledger_account before insert or update of practice_id,account_id on public.billing_ledger_entry
for each row execute function public.enforce_same_practice_reference('billing_account','account_id');
create trigger tenant_guard_statement_account before insert or update of practice_id,account_id on public.billing_statement
for each row execute function public.enforce_same_practice_reference('billing_account','account_id');
