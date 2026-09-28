
create index if not exists billing_invoice_liability_practice_idx on public.billing_invoice_liability(practice_id);
create index if not exists billing_ledger_reversal_idx on public.billing_ledger_entry(reversal_of_entry_id) where reversal_of_entry_id is not null;
create index if not exists billing_quote_converted_invoice_idx on public.billing_quote(converted_invoice_id) where converted_invoice_id is not null;
create index if not exists billing_quote_line_code_system_idx on public.billing_quote_line(code_system) where code_system is not null;
create index if not exists practice_billing_profile_updated_by_idx on public.practice_billing_profile(updated_by) where updated_by is not null;

drop policy if exists practice_billing_profile_manage on public.practice_billing_profile;
create policy practice_billing_profile_insert on public.practice_billing_profile for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice_billing_profile.practice_id and m.active and m.role in ('practice_manager','system_admin'))
);
create policy practice_billing_profile_update on public.practice_billing_profile for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice_billing_profile.practice_id and m.active and m.role in ('practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice_billing_profile.practice_id and m.active and m.role in ('practice_manager','system_admin'))
);

drop policy if exists billing_account_manage on public.billing_account;
create policy billing_account_insert on public.billing_account for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_account_update on public.billing_account for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_document_sequence_posting_manage on public.billing_document_sequence;
create policy billing_document_sequence_posting_insert on public.billing_document_sequence for insert to authenticated with check (
  (select current_setting('practicectrl.billing_sequence',true))='on'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_document_sequence.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_document_sequence_posting_update on public.billing_document_sequence for update to authenticated using (
  (select current_setting('practicectrl.billing_sequence',true))='on'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_document_sequence.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  (select current_setting('practicectrl.billing_sequence',true))='on'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_document_sequence.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_quote_manage on public.billing_quote;
create policy billing_quote_insert on public.billing_quote for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_quote_update on public.billing_quote for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_quote_line_manage on public.billing_quote_line;
create policy billing_quote_line_insert on public.billing_quote_line for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_quote_line_update on public.billing_quote_line for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_quote_line_delete on public.billing_quote_line for delete to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_quote q join public.practice_staff_member m on m.practice_id=q.practice_id where q.id=billing_quote_line.quote_id and q.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_invoice_liability_manage on public.billing_invoice_liability;
create policy billing_invoice_liability_insert on public.billing_invoice_liability for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_liability.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_invoice_liability_update on public.billing_invoice_liability for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_liability.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_liability.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_invoice_liability_delete on public.billing_invoice_liability for delete to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_invoice_liability.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_credit_note_manage on public.billing_credit_note;
create policy billing_credit_note_insert on public.billing_credit_note for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_credit_note_update on public.billing_credit_note for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2' and billing_credit_note.status='draft'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_credit_note.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_credit_note_line_manage on public.billing_credit_note_line;
create policy billing_credit_note_line_insert on public.billing_credit_note_line for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_credit_note_line_update on public.billing_credit_note_line for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
) with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_credit_note_line_delete on public.billing_credit_note_line for delete to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_credit_note c join public.practice_staff_member m on m.practice_id=c.practice_id where c.id=billing_credit_note_line.credit_note_id and c.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_ledger_posting_insert on public.billing_ledger_entry;
create policy billing_ledger_posting_insert on public.billing_ledger_entry for insert to authenticated with check (
  (select current_setting('practicectrl.billing_posting',true))='on'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_ledger_entry.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_statement_insert on public.billing_statement;
create policy billing_statement_insert on public.billing_statement for insert to authenticated with check (
  (select current_setting('practicectrl.billing_statement_generation',true))='on'
  and generated_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_statement.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);
drop policy if exists billing_statement_line_insert on public.billing_statement_line;
create policy billing_statement_line_insert on public.billing_statement_line for insert to authenticated with check (
  (select current_setting('practicectrl.billing_statement_generation',true))='on'
  and exists(select 1 from public.billing_statement s join public.practice_staff_member m on m.practice_id=s.practice_id
    where s.id=billing_statement_line.statement_id and s.generated_by=(select auth.uid())
      and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

