drop policy if exists billing_statement_insert on public.billing_statement;
drop policy if exists billing_statement_line_insert on public.billing_statement_line;

create policy billing_statement_insert on public.billing_statement for insert to authenticated with check (
  coalesce(current_setting('practicectrl.billing_statement_generation',true),'')='on'
  and generated_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_statement.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);
create policy billing_statement_line_insert on public.billing_statement_line for insert to authenticated with check (
  coalesce(current_setting('practicectrl.billing_statement_generation',true),'')='on'
  and exists(select 1 from public.billing_statement s join public.practice_staff_member m on m.practice_id=s.practice_id
    where s.id=billing_statement_line.statement_id and s.generated_by=(select auth.uid())
      and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create or replace function public.guard_billing_quote_lifecycle()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.status<>'draft' and (
    old.practice_id is distinct from new.practice_id or old.account_id is distinct from new.account_id or
    old.patient_id is distinct from new.patient_id or old.encounter_id is distinct from new.encounter_id or
    old.quote_number is distinct from new.quote_number or old.subtotal_amount is distinct from new.subtotal_amount or
    old.tax_amount is distinct from new.tax_amount or old.total_amount is distinct from new.total_amount or
    old.supplier_snapshot is distinct from new.supplier_snapshot or old.recipient_snapshot is distinct from new.recipient_snapshot
  ) and coalesce(current_setting('practicectrl.billing_quote_lifecycle',true),'')<>'on' then raise exception 'Issued quote financial/provenance fields are immutable'; end if;
  if old.status is distinct from new.status and old.status<>'draft' and coalesce(current_setting('practicectrl.billing_quote_lifecycle',true),'')<>'on' then raise exception 'Quote lifecycle changes must use the governed quote action'; end if;
  if old.status='draft' and new.status<>'draft' and coalesce(current_setting('practicectrl.billing_quote_lifecycle',true),'')<>'on' then raise exception 'Quote issue/acceptance must use the governed quote action'; end if;
  return new;
end; $$;
drop trigger if exists trg_guard_billing_quote_lifecycle on public.billing_quote;
create trigger trg_guard_billing_quote_lifecycle before update on public.billing_quote for each row execute function public.guard_billing_quote_lifecycle();

create or replace function public.set_billing_quote_status(p_quote_id uuid,p_status text)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_quote public.billing_quote%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_status not in ('sent','accepted','rejected','void') then raise exception 'Invalid quote lifecycle action'; end if;
  select * into v_quote from public.billing_quote where id=p_quote_id for update;
  if not found then raise exception 'Quote not found or not accessible'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  if v_quote.status='converted' then raise exception 'Converted quote cannot change status'; end if;
  if p_status='accepted' and v_quote.status not in ('draft','sent') then raise exception 'Only draft or sent quotes can be accepted'; end if;
  if p_status='sent' and v_quote.status<>'draft' then raise exception 'Only draft quotes can be marked sent'; end if;
  if p_status in ('rejected','void') and v_quote.status not in ('draft','sent','accepted') then raise exception 'Quote cannot move to requested status'; end if;
  perform set_config('practicectrl.billing_quote_lifecycle','on',true);
  update public.billing_quote set status=p_status,sent_at=case when p_status='sent' then now() else sent_at end,
    accepted_at=case when p_status='accepted' then now() else accepted_at end,rejected_at=case when p_status='rejected' then now() else rejected_at end,updated_at=now()
  where id=p_quote_id;
  insert into public.billing_quote_event(quote_id,event_type,actor_user_id,metadata) values(p_quote_id,p_status,v_user,jsonb_build_object('previous_status',v_quote.status));
  return p_quote_id;
end; $$;

create or replace function public.convert_billing_quote_to_invoice(p_quote_id uuid)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_quote public.billing_quote%rowtype; v_invoice_id uuid; v_kind text; v_line record;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_quote from public.billing_quote where id=p_quote_id for update;
  if not found then raise exception 'Quote not found or not accessible'; end if;
  if v_quote.status<>'accepted' then raise exception 'Only an accepted quote can be converted'; end if;
  if v_quote.converted_invoice_id is not null then return v_quote.converted_invoice_id; end if;
  if not exists(select 1 from public.billing_quote_line where quote_id=p_quote_id) then raise exception 'Quote has no lines'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select case when bool_and(line_type='clinical') then 'clinical' when bool_and(line_type='transactional') then 'transactional' else 'mixed' end into v_kind from public.billing_quote_line where quote_id=p_quote_id;
  v_invoice_id:=public.create_revenue_invoice(v_quote.practice_id,v_quote.account_id,v_kind,v_quote.patient_id,v_quote.encounter_id,current_date,null,v_quote.reference,v_quote.notes,v_quote.terms);
  update public.billing_invoice set quote_id=p_quote_id where id=v_invoice_id;
  for v_line in select * from public.billing_quote_line where quote_id=p_quote_id order by line_no loop
    perform public.add_revenue_invoice_line(v_invoice_id,v_line.line_type,v_line.description,v_line.quantity,v_line.unit_amount,
      coalesce((select service_date from public.practice_encounter where id=v_quote.encounter_id),current_date),
      v_line.code_system,v_line.code,v_line.modifier_codes,v_line.diagnosis_codes,v_line.tax_rate,v_line.claim_eligible);
  end loop;
  perform set_config('practicectrl.billing_quote_lifecycle','on',true);
  update public.billing_quote set status='converted',converted_invoice_id=v_invoice_id,converted_at=now(),updated_at=now() where id=p_quote_id;
  insert into public.billing_quote_event(quote_id,event_type,actor_user_id,metadata) values(p_quote_id,'converted',v_user,jsonb_build_object('invoice_id',v_invoice_id));
  return v_invoice_id;
end; $$;

create or replace function public.guard_billing_credit_note_lifecycle()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.status<>'draft' and (
    old.practice_id is distinct from new.practice_id or old.account_id is distinct from new.account_id or
    old.invoice_id is distinct from new.invoice_id or old.credit_note_number is distinct from new.credit_note_number or
    old.total_amount is distinct from new.total_amount or old.tax_amount is distinct from new.tax_amount or
    old.supplier_snapshot is distinct from new.supplier_snapshot or old.recipient_snapshot is distinct from new.recipient_snapshot
  ) and coalesce(current_setting('practicectrl.billing_posting',true),'')<>'on' then raise exception 'Final credit note financial/provenance fields are immutable'; end if;
  if old.status='draft' and new.status<>'draft' and coalesce(current_setting('practicectrl.billing_posting',true),'')<>'on' then raise exception 'Credit note finalisation must use the governed billing action'; end if;
  return new;
end; $$;
drop trigger if exists trg_guard_billing_credit_note_lifecycle on public.billing_credit_note;
create trigger trg_guard_billing_credit_note_lifecycle before update on public.billing_credit_note for each row execute function public.guard_billing_credit_note_lifecycle();

create or replace function public.create_billing_credit_note(p_invoice_id uuid,p_account_id uuid,p_reason text,p_description text,p_amount numeric,p_tax_amount numeric default 0,p_credit_note_date date default current_date)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_invoice public.billing_invoice%rowtype; v_id uuid := gen_random_uuid(); v_number text; v_base numeric(14,2); v_existing numeric(14,2); v_liability numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_reason,'')))<3 or length(trim(coalesce(p_description,'')))<2 then raise exception 'Credit reason and description are required'; end if;
  if coalesce(p_amount,0)<=0 or coalesce(p_tax_amount,0)<0 or p_tax_amount>p_amount then raise exception 'Invalid credit amount'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id;
  if not found or v_invoice.status='draft' or v_invoice.status='void' then raise exception 'A finalised invoice is required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select amount into v_liability from public.billing_invoice_liability where invoice_id=p_invoice_id and account_id=p_account_id;
  if v_liability is null then raise exception 'Account is not a liable party on this invoice'; end if;
  select coalesce(sum(total_amount),0) into v_existing from public.billing_credit_note where invoice_id=p_invoice_id and account_id=p_account_id and status='final';
  if round(v_existing+p_amount,2)>round(v_liability,2) then raise exception 'Credit notes cannot exceed this account liability on the invoice'; end if;
  v_number:=public.next_billing_document_number(v_invoice.practice_id,'credit_note',coalesce(p_credit_note_date,current_date)); v_base:=p_amount-coalesce(p_tax_amount,0);
  insert into public.billing_credit_note(id,practice_id,account_id,invoice_id,credit_note_number,credit_note_date,status,currency,subtotal_amount,tax_amount,total_amount,reason,supplier_snapshot,recipient_snapshot,created_by)
  values(v_id,v_invoice.practice_id,p_account_id,p_invoice_id,v_number,coalesce(p_credit_note_date,current_date),'draft',v_invoice.currency,v_base,coalesce(p_tax_amount,0),p_amount,trim(p_reason),public.billing_supplier_snapshot(v_invoice.practice_id),public.billing_recipient_snapshot(p_account_id),v_user);
  insert into public.billing_credit_note_line(credit_note_id,line_no,description,quantity,unit_amount,tax_rate,tax_amount,line_amount)
  values(v_id,1,trim(p_description),1,v_base,case when v_base=0 then 0 else coalesce(p_tax_amount,0)/v_base end,coalesce(p_tax_amount,0),p_amount);
  insert into public.billing_credit_note_event(credit_note_id,event_type,actor_user_id,metadata)
  values(v_id,'created',v_user,jsonb_build_object('invoice_id',p_invoice_id,'credit_note_number',v_number,'amount',p_amount));
  return v_id;
end; $$;

create or replace function public.finalise_billing_credit_note(p_credit_note_id uuid)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_credit public.billing_credit_note%rowtype; v_invoice public.billing_invoice%rowtype;
  v_line_total numeric(14,2); v_line_tax numeric(14,2); v_liability numeric(14,2); v_existing numeric(14,2); v_new_credit numeric(14,2); v_new_balance numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_credit from public.billing_credit_note where id=p_credit_note_id for update;
  if not found or v_credit.status<>'draft' then raise exception 'Draft credit note required'; end if;
  select * into v_invoice from public.billing_invoice where id=v_credit.invoice_id for update;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_credit.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select coalesce(sum(line_amount),0),coalesce(sum(tax_amount),0) into v_line_total,v_line_tax from public.billing_credit_note_line where credit_note_id=p_credit_note_id;
  if round(v_line_total,2)<>round(v_credit.total_amount,2) or round(v_line_tax,2)<>round(v_credit.tax_amount,2) then raise exception 'Credit note line totals do not reconcile'; end if;
  select amount into v_liability from public.billing_invoice_liability where invoice_id=v_credit.invoice_id and account_id=v_credit.account_id;
  select coalesce(sum(total_amount),0) into v_existing from public.billing_credit_note where invoice_id=v_credit.invoice_id and account_id=v_credit.account_id and status='final' and id<>v_credit.id;
  if v_liability is null or round(v_existing+v_credit.total_amount,2)>round(v_liability,2) then raise exception 'Credit exceeds account liability on source invoice'; end if;
  perform set_config('practicectrl.billing_posting','on',true);
  update public.billing_credit_note set status='final',finalised_by=v_user,finalised_at=now(),updated_at=now() where id=p_credit_note_id;
  v_new_credit:=v_invoice.credited_amount+v_credit.total_amount; v_new_balance:=greatest(v_invoice.total_amount-v_new_credit-v_invoice.received_amount,0);
  update public.billing_invoice set credited_amount=v_new_credit,balance_amount=v_new_balance,status=case when v_new_balance=0 then 'paid' when v_invoice.received_amount>0 then 'part_paid' else 'final' end,updated_at=now() where id=v_invoice.id;
  insert into public.billing_ledger_entry(practice_id,account_id,transaction_date,entry_type,document_number,description,signed_amount,invoice_id,credit_note_id,source_key,created_by,metadata)
  values(v_credit.practice_id,v_credit.account_id,v_credit.credit_note_date,'credit_note',v_credit.credit_note_number,'Credit note '||v_credit.credit_note_number,-v_credit.total_amount,v_credit.invoice_id,v_credit.id,'credit_note:'||v_credit.id::text,v_user,jsonb_build_object('reason',v_credit.reason));
  insert into public.billing_credit_note_event(credit_note_id,event_type,actor_user_id,metadata) values(v_credit.id,'finalised',v_user,jsonb_build_object('new_invoice_balance',v_new_balance));
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata) values(v_invoice.id,'credit_note_finalised',v_user,jsonb_build_object('credit_note_id',v_credit.id,'amount',v_credit.total_amount,'new_balance',v_new_balance));
  return v_credit.id;
end; $$;

create or replace function public.create_revenue_receipt(p_practice_id uuid,p_account_id uuid,p_receipt_date date,p_amount numeric,p_payment_method text default null,p_external_reference text default null,p_patient_id uuid default null)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_account public.billing_account%rowtype; v_id uuid := gen_random_uuid(); v_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if coalesce(p_amount,0)<=0 then raise exception 'Receipt amount must be greater than zero'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select * into v_account from public.billing_account where id=p_account_id and practice_id=p_practice_id and status='active';
  if not found then raise exception 'Active billing account required'; end if;
  if p_patient_id is not null and not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then raise exception 'Patient is not in selected practice'; end if;
  v_number:=public.next_billing_document_number(p_practice_id,'receipt',coalesce(p_receipt_date,current_date));
  insert into public.billing_payment_receipt(id,practice_id,account_id,patient_id,medical_scheme_id,payer_type,receipt_number,receipt_date,amount,payment_method,external_reference,source_system,created_by)
  values(v_id,p_practice_id,p_account_id,coalesce(p_patient_id,v_account.patient_id),v_account.medical_scheme_id,case when v_account.account_type='patient' then 'patient' when v_account.account_type='medical_scheme' then 'scheme' when v_account.account_type='insurer' then 'insurer' else 'other' end,v_number,coalesce(p_receipt_date,current_date),p_amount,nullif(trim(coalesce(p_payment_method,'')),''),nullif(trim(coalesce(p_external_reference,'')),''),'PracticeCtrl',v_user);
  perform set_config('practicectrl.billing_posting','on',true);
  insert into public.billing_ledger_entry(practice_id,account_id,transaction_date,entry_type,document_number,description,signed_amount,receipt_id,source_key,created_by,metadata)
  values(p_practice_id,p_account_id,coalesce(p_receipt_date,current_date),'receipt_allocation',v_number,'Receipt '||v_number,-p_amount,v_id,'receipt:'||v_id::text,v_user,jsonb_build_object('payment_method',p_payment_method,'external_reference',p_external_reference));
  return v_id;
end; $$;

create or replace function public.allocate_billing_receipt(p_receipt_id uuid,p_invoice_id uuid,p_amount numeric,p_claim_id uuid default null,p_note text default null)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_receipt public.billing_payment_receipt%rowtype; v_invoice public.billing_invoice%rowtype; v_account uuid;
  v_allocated numeric(14,2); v_account_allocated numeric(14,2); v_liability numeric(14,2); v_credit_for_account numeric(14,2);
  v_allocation_id uuid; v_new_received numeric(14,2); v_new_balance numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if coalesce(p_amount,0)<=0 then raise exception 'Allocation amount must be greater than zero'; end if;
  select * into v_receipt from public.billing_payment_receipt where id=p_receipt_id for update;
  if not found then raise exception 'Receipt not found or not accessible'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if v_invoice.practice_id<>v_receipt.practice_id then raise exception 'Receipt and invoice belong to different practices'; end if;
  if v_invoice.status='draft' or v_invoice.status='void' then raise exception 'Receipt can only be allocated to a finalised invoice'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  v_account:=v_receipt.account_id;
  if v_account is null then
    select account_id into v_account from public.billing_invoice_liability where invoice_id=p_invoice_id limit 2;
    if (select count(*) from public.billing_invoice_liability where invoice_id=p_invoice_id)<>1 then raise exception 'Receipt account is required for a split-liability invoice'; end if;
    update public.billing_payment_receipt set account_id=v_account where id=p_receipt_id;
  end if;
  select amount into v_liability from public.billing_invoice_liability where invoice_id=p_invoice_id and account_id=v_account;
  if v_liability is null then raise exception 'Receipt account is not liable on this invoice'; end if;
  select coalesce(sum(amount),0) into v_allocated from public.billing_payment_allocation where receipt_id=p_receipt_id and allocation_status='posted';
  if round(v_allocated+p_amount,2)>round(abs(v_receipt.amount),2) then raise exception 'Allocation exceeds unallocated receipt amount'; end if;
  select coalesce(sum(a.amount),0) into v_account_allocated from public.billing_payment_allocation a join public.billing_payment_receipt r on r.id=a.receipt_id
  where a.invoice_id=p_invoice_id and a.allocation_status='posted' and r.account_id=v_account;
  select coalesce(sum(total_amount),0) into v_credit_for_account from public.billing_credit_note where invoice_id=p_invoice_id and account_id=v_account and status='final';
  if round(v_account_allocated+p_amount,2)>round(greatest(v_liability-v_credit_for_account,0),2) then raise exception 'Allocation exceeds this account remaining liability on the invoice'; end if;
  if p_claim_id is not null and not exists(select 1 from public.claim_record c where c.id=p_claim_id and c.practice_id=v_invoice.practice_id and (c.invoice_id is null or c.invoice_id=v_invoice.id)) then raise exception 'Claim link is not valid for this invoice/practice'; end if;
  insert into public.billing_payment_allocation(receipt_id,invoice_id,claim_id,amount,allocation_status,allocated_by,notes)
  values(p_receipt_id,p_invoice_id,p_claim_id,p_amount,'posted',v_user,p_note) returning id into v_allocation_id;
  v_new_received:=v_invoice.received_amount+p_amount; v_new_balance:=greatest(v_invoice.total_amount-v_invoice.credited_amount-v_new_received,0);
  perform set_config('practicectrl.billing_posting','on',true);
  update public.billing_invoice set received_amount=v_new_received,balance_amount=v_new_balance,status=case when v_new_balance=0 then 'paid' when v_new_received>0 then 'part_paid' else 'final' end,updated_at=now() where id=p_invoice_id;
  insert into public.billing_allocation_event(allocation_id,event_type,actor_user_id,reason,metadata)
  values(v_allocation_id,'posted',v_user,p_note,jsonb_build_object('receipt_id',p_receipt_id,'invoice_id',p_invoice_id,'account_id',v_account,'amount',p_amount));
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'payment_allocated',v_user,jsonb_build_object('allocation_id',v_allocation_id,'receipt_id',p_receipt_id,'account_id',v_account,'amount',p_amount,'new_balance',v_new_balance));
  return v_allocation_id;
end; $$;

create or replace function public.reverse_billing_allocation(p_allocation_id uuid,p_reason text)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_alloc public.billing_payment_allocation%rowtype; v_invoice public.billing_invoice%rowtype; v_new_received numeric(14,2); v_new_balance numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reversal reason is required'; end if;
  select * into v_alloc from public.billing_payment_allocation where id=p_allocation_id for update;
  if not found or v_alloc.allocation_status<>'posted' then raise exception 'Posted allocation required'; end if;
  select * into v_invoice from public.billing_invoice where id=v_alloc.invoice_id for update;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  update public.billing_payment_allocation set allocation_status='reversed' where id=p_allocation_id;
  v_new_received:=greatest(v_invoice.received_amount-v_alloc.amount,0); v_new_balance:=greatest(v_invoice.total_amount-v_invoice.credited_amount-v_new_received,0);
  perform set_config('practicectrl.billing_posting','on',true);
  update public.billing_invoice set received_amount=v_new_received,balance_amount=v_new_balance,status=case when v_new_balance=0 then 'paid' when v_new_received>0 then 'part_paid' else 'final' end,updated_at=now() where id=v_invoice.id;
  insert into public.billing_allocation_event(allocation_id,event_type,actor_user_id,reason,metadata) values(p_allocation_id,'reversed',v_user,trim(p_reason),jsonb_build_object('invoice_id',v_invoice.id,'amount',v_alloc.amount,'new_balance',v_new_balance));
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata) values(v_invoice.id,'allocation_reversed',v_user,jsonb_build_object('allocation_id',p_allocation_id,'amount',v_alloc.amount,'reason',trim(p_reason),'new_balance',v_new_balance));
  return p_allocation_id;
end; $$;

create or replace function public.get_billing_account_balance(p_account_id uuid,p_as_of date default current_date)
returns numeric language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare v_account public.billing_account%rowtype; v_balance numeric(14,2);
begin
  select * into v_account from public.billing_account where id=p_account_id;
  if not found then raise exception 'Billing account not found or not accessible'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=v_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin','auditor')) then raise exception 'Revenue access required'; end if;
  select coalesce(sum(signed_amount),0) into v_balance from public.billing_ledger_entry where account_id=p_account_id and transaction_date<=coalesce(p_as_of,current_date);
  return v_balance;
end; $$;

create or replace function public.generate_billing_statement(p_account_id uuid,p_period_from date,p_period_to date,p_statement_date date default current_date)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_account public.billing_account%rowtype; v_id uuid := gen_random_uuid(); v_number text;
  v_opening numeric(14,2); v_debits numeric(14,2); v_credits numeric(14,2); v_running numeric(14,2); v_line_no integer := 0; r record;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_period_from is null or p_period_to is null or p_period_to<p_period_from then raise exception 'Valid statement period required'; end if;
  select * into v_account from public.billing_account where id=p_account_id;
  if not found then raise exception 'Billing account not found or not accessible'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_account.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select coalesce(sum(signed_amount),0) into v_opening from public.billing_ledger_entry where account_id=p_account_id and transaction_date<p_period_from;
  select coalesce(sum(signed_amount) filter(where signed_amount>0),0),coalesce(sum(-signed_amount) filter(where signed_amount<0),0)
  into v_debits,v_credits from public.billing_ledger_entry where account_id=p_account_id and transaction_date between p_period_from and p_period_to;
  v_number:=public.next_billing_document_number(v_account.practice_id,'statement',coalesce(p_statement_date,current_date));
  perform set_config('practicectrl.billing_statement_generation','on',true);
  insert into public.billing_statement(id,practice_id,account_id,statement_number,statement_date,period_from,period_to,opening_balance,debit_total,credit_total,closing_balance,supplier_snapshot,recipient_snapshot,generated_by)
  values(v_id,v_account.practice_id,p_account_id,v_number,coalesce(p_statement_date,current_date),p_period_from,p_period_to,v_opening,v_debits,v_credits,v_opening+v_debits-v_credits,public.billing_supplier_snapshot(v_account.practice_id),public.billing_recipient_snapshot(p_account_id),v_user);
  v_running:=v_opening;
  for r in select * from public.billing_ledger_entry where account_id=p_account_id and transaction_date between p_period_from and p_period_to order by transaction_date,created_at,id loop
    v_line_no:=v_line_no+1; v_running:=v_running+r.signed_amount;
    insert into public.billing_statement_line(statement_id,line_no,ledger_entry_id,transaction_date,document_number,description,debit_amount,credit_amount,running_balance)
    values(v_id,v_line_no,r.id,r.transaction_date,r.document_number,r.description,greatest(r.signed_amount,0),greatest(-r.signed_amount,0),v_running);
  end loop;
  return v_id;
end; $$;

revoke all on function public.convert_billing_quote_to_invoice(uuid) from public,anon;
revoke all on function public.create_billing_credit_note(uuid,uuid,text,text,numeric,numeric,date) from public,anon;
revoke all on function public.finalise_billing_credit_note(uuid) from public,anon;
revoke all on function public.create_revenue_receipt(uuid,uuid,date,numeric,text,text,uuid) from public,anon;
revoke all on function public.get_billing_account_balance(uuid,date) from public,anon;
revoke all on function public.generate_billing_statement(uuid,date,date,date) from public,anon;
grant execute on function public.convert_billing_quote_to_invoice(uuid) to authenticated;
grant execute on function public.create_billing_credit_note(uuid,uuid,text,text,numeric,numeric,date) to authenticated;
grant execute on function public.finalise_billing_credit_note(uuid) to authenticated;
grant execute on function public.create_revenue_receipt(uuid,uuid,date,numeric,text,text,uuid) to authenticated;
grant execute on function public.get_billing_account_balance(uuid,date) to authenticated;
grant execute on function public.generate_billing_statement(uuid,date,date,date) to authenticated;
