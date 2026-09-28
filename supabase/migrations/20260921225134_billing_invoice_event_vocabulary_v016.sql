alter table public.billing_invoice_event drop constraint if exists billing_invoice_event_event_type_check;
alter table public.billing_invoice_event add constraint billing_invoice_event_event_type_check
check (event_type = any(array[
  'created','line_added','line_removed','validated','finalised','payment_allocated','allocation_reversed',
  'adjusted','credit_note','credit_note_finalised','voided','statement_generated','other'
]::text[]));
