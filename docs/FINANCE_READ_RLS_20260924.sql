-- Finance read-access alignment for controlled staging.
--
-- This migration adds the finance role only to existing financial SELECT policies.
-- It intentionally creates no Finance INSERT, UPDATE, DELETE, function-execute,
-- or credential privilege. Every policy retains active same-practice membership.

alter policy billing_credit_note_read on public.billing_credit_note using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = billing_credit_note.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy billing_invoice_finance_read on public.billing_invoice using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = billing_invoice.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy billing_invoice_line_finance_read on public.billing_invoice_line using (
  exists (select 1 from public.billing_invoice i
    join public.practice_staff_member m on m.practice_id = i.practice_id
    where i.id = billing_invoice_line.invoice_id and m.user_id = (select auth.uid())
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy billing_ledger_read on public.billing_ledger_entry using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = billing_ledger_entry.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy billing_allocation_finance_read on public.billing_payment_allocation using (
  exists (select 1 from public.billing_payment_receipt r
    join public.practice_staff_member m on m.practice_id = r.practice_id
    where r.id = billing_payment_allocation.receipt_id and m.user_id = (select auth.uid())
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy billing_receipt_finance_read on public.billing_payment_receipt using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = billing_payment_receipt.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy billing_quote_read on public.billing_quote using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = billing_quote.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy billing_quote_line_read on public.billing_quote_line using (
  exists (select 1 from public.billing_quote q
    join public.practice_staff_member m on m.practice_id = q.practice_id
    where q.id = billing_quote_line.quote_id and m.user_id = (select auth.uid())
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy claim_line_finance_read on public.claim_line using (
  exists (select 1 from public.claim_record c
    join public.practice_staff_member m on m.practice_id = c.practice_id
    where c.id = claim_line.claim_id and m.user_id = (select auth.uid())
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy claim_record_finance_read on public.claim_record using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = claim_record.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy remittance_advice_finance_read on public.remittance_advice using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = remittance_advice.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy remittance_line_finance_read on public.remittance_line using (
  exists (select 1 from public.remittance_advice r
    join public.practice_staff_member m on m.practice_id = r.practice_id
    where r.id = remittance_line.remittance_id and m.user_id = (select auth.uid())
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy revenue_snapshot_finance_read on public.revenue_account_snapshot using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = revenue_account_snapshot.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy vericlaim_receipt_finance_read on public.vericlaim_funder_receipt using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = vericlaim_funder_receipt.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy vericlaim_receipt_alloc_finance_read on public.vericlaim_funder_receipt_allocation using (
  exists (select 1 from public.vericlaim_funder_receipt r
    join public.practice_staff_member m on m.practice_id = r.practice_id
    where r.id = vericlaim_funder_receipt_allocation.receipt_id and m.user_id = (select auth.uid())
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy vericlaim_import_privileged_read on public.vericlaim_import_batch using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = vericlaim_import_batch.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy vericlaim_invoice_snapshot_finance_read on public.vericlaim_invoice_snapshot using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = vericlaim_invoice_snapshot.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);

alter policy vericlaim_credit_finance_read on public.vericlaim_scheme_credit_snapshot using (
  exists (select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid()) and m.practice_id = vericlaim_scheme_credit_snapshot.practice_id
      and m.active and m.role in ('billing', 'finance', 'practice_manager', 'system_admin', 'auditor'))
);
