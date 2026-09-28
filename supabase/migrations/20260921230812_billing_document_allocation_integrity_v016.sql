
-- Authenticated PracticeCtrl document creation must pass through governed actions.
drop policy if exists billing_invoice_finance_insert on public.billing_invoice;
create policy billing_invoice_finance_insert on public.billing_invoice for insert to authenticated with check (
  (select current_setting('practicectrl.billing_document_creation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_quote_insert on public.billing_quote;
create policy billing_quote_insert on public.billing_quote for insert to authenticated with check (
  (select current_setting('practicectrl.billing_document_creation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_credit_note_insert on public.billing_credit_note;
create policy billing_credit_note_insert on public.billing_credit_note for insert to authenticated with check (
  (select current_setting('practicectrl.billing_document_creation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_receipt_finance_insert on public.billing_payment_receipt;
create policy billing_receipt_finance_insert on public.billing_payment_receipt for insert to authenticated with check (
  (select current_setting('practicectrl.billing_document_creation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_payment_receipt.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_invoice_line_finance_insert on public.billing_invoice_line;
create policy billing_invoice_line_finance_insert on public.billing_invoice_line for insert to authenticated with check (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id
    where i.id=billing_invoice_line.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_quote_line_insert on public.billing_quote_line;
drop policy if exists billing_quote_line_update on public.billing_quote_line;
drop policy if exists billing_quote_line_delete on public.billing_quote_line;
create policy billing_quote_line_insert on public.billing_quote_line for insert to authenticated with check (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id
    where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_quote_line_update on public.billing_quote_line for update to authenticated using (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id
    where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id
    where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_quote_line_delete on public.billing_quote_line for delete to authenticated using (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id
    where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_credit_note_line_insert on public.billing_credit_note_line;
drop policy if exists billing_credit_note_line_update on public.billing_credit_note_line;
drop policy if exists billing_credit_note_line_delete on public.billing_credit_note_line;
create policy billing_credit_note_line_insert on public.billing_credit_note_line for insert to authenticated with check (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id
    where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_credit_note_line_update on public.billing_credit_note_line for update to authenticated using (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id
    where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id
    where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_credit_note_line_delete on public.billing_credit_note_line for delete to authenticated using (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id
    where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_allocation_finance_insert on public.billing_payment_allocation;
drop policy if exists billing_allocation_finance_update on public.billing_payment_allocation;
create policy billing_allocation_finance_insert on public.billing_payment_allocation for insert to authenticated with check (
  (select current_setting('practicectrl.billing_allocation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and allocated_by=(select auth.uid())
  and exists(select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_allocation_finance_update on public.billing_payment_allocation for update to authenticated using (
  (select current_setting('practicectrl.billing_allocation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  (select current_setting('practicectrl.billing_allocation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

alter table public.billing_ledger_entry drop constraint if exists billing_ledger_entry_entry_type_check;
alter table public.billing_ledger_entry add constraint billing_ledger_entry_entry_type_check
check (entry_type in ('invoice','credit_note','receipt','receipt_allocation','allocation_reversal','writeoff','adjustment','opening_balance'));
update public.billing_ledger_entry set entry_type='receipt'
where entry_type='receipt_allocation' and receipt_id is not null and allocation_id is null;

create or replace function public.guard_billing_receipt_integrity()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.practice_id is distinct from new.practice_id
     or old.patient_id is distinct from new.patient_id
     or old.medical_scheme_id is distinct from new.medical_scheme_id
     or old.payer_type is distinct from new.payer_type
     or old.receipt_number is distinct from new.receipt_number
     or old.receipt_date is distinct from new.receipt_date
     or old.amount is distinct from new.amount
     or old.payment_method is distinct from new.payment_method
     or old.external_reference is distinct from new.external_reference
     or old.source_system is distinct from new.source_system
     or old.created_by is distinct from new.created_by
     or old.supplier_snapshot is distinct from new.supplier_snapshot then
    raise exception 'Posted receipt financial/provenance fields are immutable';
  end if;
  if old.account_id is distinct from new.account_id then
    if old.account_id is not null or new.account_id is null then raise exception 'Receipt account cannot be reassigned'; end if;
    if old.recipient_snapshot is distinct from new.recipient_snapshot and new.recipient_snapshot='{}'::jsonb then raise exception 'Recipient snapshot required when assigning receipt account'; end if;
  elsif old.recipient_snapshot is distinct from new.recipient_snapshot then
    raise exception 'Receipt recipient snapshot is immutable';
  end if;
  return new;
end; $$;
drop trigger if exists trg_guard_billing_receipt_integrity on public.billing_payment_receipt;
create trigger trg_guard_billing_receipt_integrity before update on public.billing_payment_receipt
for each row execute function public.guard_billing_receipt_integrity();

create or replace function public.guard_billing_allocation_integrity()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.receipt_id is distinct from new.receipt_id
    or old.invoice_id is distinct from new.invoice_id
    or old.claim_id is distinct from new.claim_id
    or old.amount is distinct from new.amount
    or old.allocated_by is distinct from new.allocated_by
    or old.allocated_at is distinct from new.allocated_at then
    raise exception 'Payment allocation provenance is immutable';
  end if;
  if old.allocation_status is distinct from new.allocation_status
     and (select current_setting('practicectrl.billing_allocation',true))<>'on' then
    raise exception 'Allocation lifecycle changes require the governed allocation action';
  end if;
  return new;
end; $$;
drop trigger if exists trg_guard_billing_allocation_integrity on public.billing_payment_allocation;
create trigger trg_guard_billing_allocation_integrity before update on public.billing_payment_allocation
for each row execute function public.guard_billing_allocation_integrity();

create or replace function public.guard_billing_quote_lifecycle()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.status<>'draft' and (
    old.practice_id is distinct from new.practice_id or old.account_id is distinct from new.account_id or
    old.patient_id is distinct from new.patient_id or old.encounter_id is distinct from new.encounter_id or
    old.quote_number is distinct from new.quote_number or old.quote_date is distinct from new.quote_date or
    old.valid_until is distinct from new.valid_until or old.currency is distinct from new.currency or
    old.subtotal_amount is distinct from new.subtotal_amount or old.tax_amount is distinct from new.tax_amount or
    old.total_amount is distinct from new.total_amount or old.reference is distinct from new.reference or
    old.notes is distinct from new.notes or old.terms is distinct from new.terms or
    old.supplier_snapshot is distinct from new.supplier_snapshot or old.recipient_snapshot is distinct from new.recipient_snapshot or
    old.created_by is distinct from new.created_by
  ) and (select current_setting('practicectrl.billing_quote_lifecycle',true))<>'on' then
    raise exception 'Issued quote content/provenance is immutable';
  end if;
  if old.status is distinct from new.status and (select current_setting('practicectrl.billing_quote_lifecycle',true))<>'on' then
    raise exception 'Quote lifecycle changes must use the governed quote action';
  end if;
  return new;
end; $$;

create or replace function public.guard_billing_invoice_lifecycle()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.status<>'draft' and (
    old.practice_id is distinct from new.practice_id or old.account_id is distinct from new.account_id or
    old.patient_id is distinct from new.patient_id or old.encounter_id is distinct from new.encounter_id or
    old.invoice_number is distinct from new.invoice_number or old.invoice_date is distinct from new.invoice_date or
    old.due_date is distinct from new.due_date or old.currency is distinct from new.currency or
    old.invoice_kind is distinct from new.invoice_kind or old.medical_scheme_id is distinct from new.medical_scheme_id or
    old.medical_scheme_option_id is distinct from new.medical_scheme_option_id or
    old.scheme_authorisation_id is distinct from new.scheme_authorisation_id or
    old.total_amount is distinct from new.total_amount or old.subtotal_amount is distinct from new.subtotal_amount or
    old.tax_amount is distinct from new.tax_amount or old.credited_amount is distinct from new.credited_amount or
    old.reference is distinct from new.reference or old.notes is distinct from new.notes or old.terms is distinct from new.terms or
    old.tax_invoice is distinct from new.tax_invoice or old.supplier_snapshot is distinct from new.supplier_snapshot or
    old.recipient_snapshot is distinct from new.recipient_snapshot or old.source_system is distinct from new.source_system or
    old.created_by is distinct from new.created_by
  ) and (select current_setting('practicectrl.billing_posting',true))<>'on' then
    raise exception 'Finalised invoice financial/provenance fields are immutable';
  end if;
  if old.status='draft' and new.status<>'draft' and (select current_setting('practicectrl.billing_posting',true))<>'on' then
    raise exception 'Invoice finalisation must use the governed billing action';
  end if;
  return new;
end; $$;

create or replace function public.guard_billing_credit_note_lifecycle()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.status<>'draft' and (
    old.practice_id is distinct from new.practice_id or old.account_id is distinct from new.account_id or
    old.invoice_id is distinct from new.invoice_id or old.credit_note_number is distinct from new.credit_note_number or
    old.credit_note_date is distinct from new.credit_note_date or old.currency is distinct from new.currency or
    old.total_amount is distinct from new.total_amount or old.subtotal_amount is distinct from new.subtotal_amount or
    old.tax_amount is distinct from new.tax_amount or old.reason is distinct from new.reason or
    old.supplier_snapshot is distinct from new.supplier_snapshot or old.recipient_snapshot is distinct from new.recipient_snapshot or
    old.created_by is distinct from new.created_by
  ) and (select current_setting('practicectrl.billing_posting',true))<>'on' then
    raise exception 'Final credit note content/provenance is immutable';
  end if;
  if old.status='draft' and new.status<>'draft' and (select current_setting('practicectrl.billing_posting',true))<>'on' then
    raise exception 'Credit note finalisation must use the governed billing action';
  end if;
  return new;
end; $$;

