
-- Lock numbered financial-document creation to governed RPC endpoints at the Data API boundary.
-- SECURITY INVOKER remains in force; tenant RLS and AAL2 checks inside each RPC still apply.

drop policy if exists billing_invoice_finance_insert on public.billing_invoice;
create policy billing_invoice_finance_insert on public.billing_invoice
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and coalesce(current_setting('request.path',true),'') = any(array[
    '/rpc/create_revenue_invoice',
    '/rpc/convert_billing_quote_to_invoice',
    '/rpc/create_practice_custom_invoice',
    '/rpc/create_encounter_private_invoice'
  ])
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_invoice.practice_id
      and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_quote_insert on public.billing_quote;
create policy billing_quote_insert on public.billing_quote
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and coalesce(current_setting('request.path',true),'')='/rpc/create_revenue_quote'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id
      and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_receipt_finance_insert on public.billing_payment_receipt;
create policy billing_receipt_finance_insert on public.billing_payment_receipt
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and coalesce(current_setting('request.path',true),'') = any(array[
    '/rpc/create_revenue_receipt',
    '/rpc/create_billing_receipt'
  ])
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_payment_receipt.practice_id
      and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_credit_note_insert on public.billing_credit_note;
create policy billing_credit_note_insert on public.billing_credit_note
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and coalesce(current_setting('request.path',true),'')='/rpc/create_billing_credit_note'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id
      and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_payment_allocation_finance_insert on public.billing_payment_allocation;
drop policy if exists billing_payment_allocation_insert on public.billing_payment_allocation;
create policy billing_payment_allocation_rpc_insert on public.billing_payment_allocation
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and coalesce(current_setting('request.path',true),'')='/rpc/allocate_billing_receipt'
  and allocated_by=(select auth.uid())
  and exists(
    select 1
    from public.billing_payment_receipt r
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=billing_payment_allocation.receipt_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('billing','practice_manager','system_admin')
  )
);

