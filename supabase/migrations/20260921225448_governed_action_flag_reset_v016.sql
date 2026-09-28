
create or replace function public.next_billing_document_number(p_practice_id uuid,p_document_type text,p_document_date date default current_date)
returns text language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_seq public.billing_document_sequence%rowtype;
  v_year integer := extract(year from coalesce(p_document_date,current_date))::integer; v_prefix text; v_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_document_type not in ('invoice','quote','credit_note','receipt','statement') then raise exception 'Unsupported billing document type'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  v_prefix:=case p_document_type when 'invoice' then 'INV-' when 'quote' then 'QUO-' when 'credit_note' then 'CRN-' when 'receipt' then 'REC-' when 'statement' then 'STM-' end;
  perform set_config('practicectrl.billing_sequence','on',true);
  insert into public.billing_document_sequence(practice_id,document_type,prefix,current_year)
  values(p_practice_id,p_document_type,v_prefix,v_year) on conflict(practice_id,document_type) do nothing;
  select * into v_seq from public.billing_document_sequence where practice_id=p_practice_id and document_type=p_document_type for update;
  if v_seq.annual_reset and v_seq.current_year<>v_year then
    update public.billing_document_sequence set next_value=1,current_year=v_year,updated_at=now()
    where practice_id=p_practice_id and document_type=p_document_type returning * into v_seq;
  end if;
  v_number:=v_seq.prefix||case when v_seq.include_year then v_year::text||'-' else '' end||lpad(v_seq.next_value::text,v_seq.padding,'0');
  update public.billing_document_sequence set next_value=next_value+1,updated_at=now()
  where practice_id=p_practice_id and document_type=p_document_type;
  perform set_config('practicectrl.billing_sequence','off',true);
  return v_number;
end; $$;

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
  perform set_config('practicectrl.billing_quote_lifecycle','off',true);
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
  perform set_config('practicectrl.billing_quote_lifecycle','off',true);
  return v_invoice_id;
end; $$;

create or replace function public.finalise_billing_invoice(p_invoice_id uuid)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_invoice public.billing_invoice%rowtype; v_profile public.practice_billing_profile%rowtype;
  v_line_count integer; v_subtotal numeric(14,2); v_tax numeric(14,2); v_total numeric(14,2); v_liability_total numeric(14,2); v_account uuid; v_kind text; r record;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if v_invoice.status<>'draft' then raise exception 'Only draft invoices can be finalised'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select count(*),coalesce(sum(line_amount-tax_amount),0),coalesce(sum(tax_amount),0),coalesce(sum(line_amount),0),
         case when bool_and(line_type='clinical') then 'clinical' when bool_and(line_type='transactional') then 'transactional' else 'mixed' end
  into v_line_count,v_subtotal,v_tax,v_total,v_kind from public.billing_invoice_line where invoice_id=p_invoice_id;
  if v_line_count<1 then raise exception 'Invoice has no lines'; end if;
  if v_invoice.account_id is null then
    if v_invoice.patient_id is null then raise exception 'A liable billing account is required before finalisation'; end if;
    v_account:=public.ensure_patient_billing_account(v_invoice.practice_id,v_invoice.patient_id);
    update public.billing_invoice set account_id=v_account,recipient_snapshot=public.billing_recipient_snapshot(v_account) where id=p_invoice_id;
    v_invoice.account_id:=v_account;
  end if;
  if not exists(select 1 from public.billing_invoice_liability where invoice_id=p_invoice_id) then
    insert into public.billing_invoice_liability(practice_id,invoice_id,account_id,liability_type,amount)
    select v_invoice.practice_id,p_invoice_id,a.id,case when a.account_type='patient' then 'patient' when a.account_type='medical_scheme' then 'scheme' else 'other' end,v_total
    from public.billing_account a where a.id=v_invoice.account_id;
  end if;
  select coalesce(sum(amount),0) into v_liability_total from public.billing_invoice_liability where invoice_id=p_invoice_id;
  if round(v_liability_total,2)<>round(v_total,2) then raise exception 'Invoice liability split must equal invoice total'; end if;
  select * into v_profile from public.practice_billing_profile where practice_id=v_invoice.practice_id;
  if v_tax>0 and not coalesce(v_profile.vat_registered,false) then raise exception 'VAT cannot be charged because this practice is not configured as VAT registered'; end if;
  if coalesce(v_profile.vat_registered,false) and nullif(trim(coalesce(v_profile.vat_registration_number,'')),'') is null then raise exception 'VAT registration number is required before issuing a tax invoice'; end if;
  if exists(select 1 from public.billing_validation_event e where e.invoice_id=p_invoice_id and e.severity='blocking' and e.status in ('open','acknowledged')) then raise exception 'Unresolved blocking billing validation exists'; end if;
  perform set_config('practicectrl.billing_posting','on',true);
  update public.billing_invoice set invoice_kind=v_kind,subtotal_amount=v_subtotal,tax_amount=v_tax,total_amount=v_total,
    patient_portion=coalesce((select sum(amount) from public.billing_invoice_liability where invoice_id=p_invoice_id and liability_type='patient'),0),
    scheme_portion=coalesce((select sum(amount) from public.billing_invoice_liability where invoice_id=p_invoice_id and liability_type='scheme'),0),
    balance_amount=greatest(v_total-credited_amount-received_amount,0),tax_invoice=coalesce(v_profile.vat_registered,false),
    supplier_snapshot=public.billing_supplier_snapshot(v_invoice.practice_id),recipient_snapshot=public.billing_recipient_snapshot(v_invoice.account_id),
    status=case when greatest(v_total-credited_amount-received_amount,0)=0 then 'paid' else 'final' end,
    finalised_by=v_user,finalised_at=now(),updated_at=now()
  where id=p_invoice_id;
  for r in select * from public.billing_invoice_liability where invoice_id=p_invoice_id and amount>0 loop
    insert into public.billing_ledger_entry(practice_id,account_id,transaction_date,entry_type,document_number,description,signed_amount,invoice_id,source_key,created_by,metadata)
    values(v_invoice.practice_id,r.account_id,v_invoice.invoice_date,'invoice',v_invoice.invoice_number,'Invoice '||v_invoice.invoice_number,r.amount,p_invoice_id,'invoice:'||p_invoice_id::text||':'||r.id::text,v_user,jsonb_build_object('liability_type',r.liability_type))
    on conflict(practice_id,source_key) do nothing;
  end loop;
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'finalised',v_user,jsonb_build_object('line_count',v_line_count,'total_amount',v_total,'tax_amount',v_tax,'liability_total',v_liability_total,'invoice_kind',v_kind));
  perform set_config('practicectrl.billing_posting','off',true);
  return p_invoice_id;
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
  perform set_config('practicectrl.billing_posting','off',true);
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
  perform set_config('practicectrl.billing_posting','off',true);
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
  perform set_config('practicectrl.billing_posting','off',true);
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
  perform set_config('practicectrl.billing_posting','off',true);
  return p_allocation_id;
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
  perform set_config('practicectrl.billing_statement_generation','off',true);
  return v_id;
end; $$;

create or replace function public.sign_clinical_note(p_note_id uuid) returns uuid
language plpgsql security invoker set search_path=public,extensions,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_note public.clinical_note%rowtype; v_hash text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_note from public.clinical_note where id=p_note_id for update;
  if not found then raise exception 'Clinical note not found or not accessible'; end if;
  if v_note.status<>'draft' then raise exception 'Only a draft clinical note can be signed'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_note.practice_id and m.active and m.role='practitioner') then raise exception 'Practitioner role required to sign a clinical note'; end if;
  if v_note.author_user_id<>v_user and not exists(select 1 from public.practice_encounter e where e.id=v_note.encounter_id and e.practitioner_user_id=v_user) then raise exception 'Only the author or encounter practitioner may sign this note'; end if;
  if length(trim(coalesce(v_note.assessment,v_note.narrative,'')))<2 then raise exception 'Clinical assessment or narrative is required before signing'; end if;
  v_hash:=encode(extensions.digest(concat_ws('|',v_note.practice_id::text,v_note.patient_id::text,v_note.encounter_id::text,v_note.note_type,coalesce(v_note.title,''),coalesce(v_note.subjective,''),coalesce(v_note.objective,''),coalesce(v_note.assessment,''),coalesce(v_note.plan,''),coalesce(v_note.narrative,''),v_note.structured_data::text),'sha256'),'hex');
  perform set_config('practicectrl.clinical_signing','on',true);
  update public.clinical_note set status='signed',signed_by=v_user,signed_at=now(),content_sha256=v_hash,updated_at=now() where id=p_note_id;
  if v_note.amendment_of_note_id is not null then
    update public.clinical_note set status='amended',updated_at=now() where id=v_note.amendment_of_note_id and status='signed';
    insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata) values(v_note.amendment_of_note_id,'amended',v_user,jsonb_build_object('replacement_note_id',p_note_id));
  end if;
  insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata) values(p_note_id,'signed',v_user,jsonb_build_object('content_sha256',v_hash));
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(v_note.practice_id,v_note.patient_id,'clinical',now(),'Clinical note signed',coalesce(v_note.title,initcap(replace(v_note.note_type,'_',' '))),'clinical_note',p_note_id,v_user,'PracticeCtrl',jsonb_build_object('content_sha256',v_hash,'amendment_of_note_id',v_note.amendment_of_note_id));
  perform set_config('practicectrl.clinical_signing','off',true);
  return p_note_id;
end; $$;
