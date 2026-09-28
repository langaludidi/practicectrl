grant insert,update on public.billing_document_sequence to authenticated;
grant insert on public.billing_ledger_entry to authenticated;

drop policy if exists billing_document_sequence_posting_manage on public.billing_document_sequence;
create policy billing_document_sequence_posting_manage on public.billing_document_sequence
for all to authenticated
using (
  coalesce(current_setting('practicectrl.billing_sequence',true),'')='on'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_document_sequence.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
)
with check (
  coalesce(current_setting('practicectrl.billing_sequence',true),'')='on'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_document_sequence.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

drop policy if exists billing_ledger_posting_insert on public.billing_ledger_entry;
create policy billing_ledger_posting_insert on public.billing_ledger_entry
for insert to authenticated
with check (
  coalesce(current_setting('practicectrl.billing_posting',true),'')='on'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=billing_ledger_entry.practice_id and m.active and m.role in ('billing','practice_manager','system_admin'))
);

create or replace function public.billing_supplier_snapshot(p_practice_id uuid)
returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
  select jsonb_build_object(
    'practice_id',p.id,'legal_name',coalesce(bp.legal_name,p.legal_name,p.name),'trading_name',coalesce(bp.trading_name,p.name),
    'registration_number',bp.registration_number,'vat_registered',coalesce(bp.vat_registered,false),
    'vat_registration_number',bp.vat_registration_number,'address',coalesce(bp.address,'{}'::jsonb),'email',bp.email,'phone',bp.phone,
    'banking_details',coalesce(bp.banking_details,'{}'::jsonb),'country_code',p.country_code
  )
  from public.practice p left join public.practice_billing_profile bp on bp.practice_id=p.id where p.id=p_practice_id;
$$;

create or replace function public.billing_recipient_snapshot(p_account_id uuid)
returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
  select jsonb_build_object(
    'account_id',a.id,'account_number',a.account_number,'account_type',a.account_type,'display_name',a.display_name,
    'legal_name',a.legal_name,'contact_name',a.contact_name,'email',a.email,'phone',a.phone,'billing_address',a.billing_address,
    'vat_registration_number',a.vat_registration_number,'patient_id',a.patient_id,'medical_scheme_id',a.medical_scheme_id
  ) from public.billing_account a where a.id=p_account_id;
$$;

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
  return v_number;
end; $$;

create or replace function public.ensure_patient_billing_account(p_practice_id uuid,p_patient_id uuid)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_patient public.crm_patient%rowtype; v_id uuid; v_account_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select * into v_patient from public.crm_patient where id=p_patient_id and practice_id=p_practice_id;
  if not found then raise exception 'Patient not found in selected practice'; end if;
  select id into v_id from public.billing_account where practice_id=p_practice_id and patient_id=p_patient_id and account_type='patient' limit 1;
  if v_id is not null then return v_id; end if;
  v_account_number:=coalesce(nullif(trim(v_patient.account_ref),''),'PAT-'||upper(substr(replace(v_patient.id::text,'-',''),1,10)));
  insert into public.billing_account(practice_id,account_number,account_type,patient_id,display_name,email,phone,created_by,updated_by)
  values(p_practice_id,v_account_number,'patient',p_patient_id,v_patient.display_name,v_patient.primary_email,v_patient.primary_phone,v_user,v_user)
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.create_billing_account(
  p_practice_id uuid,p_account_type text,p_display_name text,p_account_number text default null,p_patient_id uuid default null,
  p_medical_scheme_id uuid default null,p_email text default null,p_phone text default null,p_payment_terms_days integer default 30
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_id uuid; v_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_account_type not in ('patient','responsible_person','medical_scheme','insurer','employer','attorney','corporate','other') then raise exception 'Invalid billing account type'; end if;
  if length(trim(coalesce(p_display_name,'')))<2 then raise exception 'Account display name is required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  if p_patient_id is not null and not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then raise exception 'Patient is not in selected practice'; end if;
  v_number:=coalesce(nullif(trim(coalesce(p_account_number,'')),''),upper(substr(p_account_type,1,3))||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)));
  insert into public.billing_account(practice_id,account_number,account_type,patient_id,medical_scheme_id,display_name,email,phone,payment_terms_days,created_by,updated_by)
  values(p_practice_id,v_number,p_account_type,p_patient_id,p_medical_scheme_id,trim(p_display_name),nullif(trim(coalesce(p_email,'')),''),nullif(trim(coalesce(p_phone,'')),''),coalesce(p_payment_terms_days,30),v_user,v_user)
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.create_revenue_quote(
  p_practice_id uuid,p_account_id uuid,p_patient_id uuid default null,p_encounter_id uuid default null,p_quote_date date default current_date,
  p_valid_until date default null,p_reference text default null,p_notes text default null,p_terms text default null
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_id uuid := gen_random_uuid(); v_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  if not exists(select 1 from public.billing_account a where a.id=p_account_id and a.practice_id=p_practice_id and a.status='active') then raise exception 'Active billing account required'; end if;
  if p_patient_id is not null and not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then raise exception 'Patient is not in selected practice'; end if;
  if p_encounter_id is not null and not exists(select 1 from public.practice_encounter e where e.id=p_encounter_id and e.practice_id=p_practice_id and (p_patient_id is null or e.patient_id=p_patient_id)) then raise exception 'Encounter does not belong to this practice/patient'; end if;
  v_number:=public.next_billing_document_number(p_practice_id,'quote',coalesce(p_quote_date,current_date));
  insert into public.billing_quote(id,practice_id,account_id,patient_id,encounter_id,quote_number,quote_date,valid_until,reference,notes,terms,supplier_snapshot,recipient_snapshot,created_by)
  values(v_id,p_practice_id,p_account_id,p_patient_id,p_encounter_id,v_number,coalesce(p_quote_date,current_date),coalesce(p_valid_until,coalesce(p_quote_date,current_date)+30),nullif(trim(coalesce(p_reference,'')),''),nullif(trim(coalesce(p_notes,'')),''),nullif(trim(coalesce(p_terms,'')),''),public.billing_supplier_snapshot(p_practice_id),public.billing_recipient_snapshot(p_account_id),v_user);
  insert into public.billing_quote_event(quote_id,event_type,actor_user_id,metadata) values(v_id,'created',v_user,jsonb_build_object('quote_number',v_number));
  return v_id;
end; $$;

create or replace function public.add_billing_quote_line(
  p_quote_id uuid,p_line_type text,p_description text,p_quantity numeric,p_unit_amount numeric,p_code_system text default null,p_code text default null,
  p_modifier_codes text[] default '{}',p_diagnosis_codes text[] default '{}',p_tax_rate numeric default null,p_claim_eligible boolean default false
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_quote public.billing_quote%rowtype; v_profile public.practice_billing_profile%rowtype;
  v_line_no integer; v_id uuid; v_base numeric(14,2); v_tax_rate numeric(7,6); v_tax numeric(14,2); v_total numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_line_type not in ('clinical','transactional') then raise exception 'Invalid quote line type'; end if;
  if length(trim(coalesce(p_description,'')))<2 then raise exception 'Description is required'; end if;
  if coalesce(p_quantity,0)<=0 or coalesce(p_unit_amount,-1)<0 then raise exception 'Quantity and unit amount are invalid'; end if;
  select * into v_quote from public.billing_quote where id=p_quote_id for update;
  if not found then raise exception 'Quote not found or not accessible'; end if;
  if v_quote.status<>'draft' then raise exception 'Only draft quotes can be edited'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_quote.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  if p_claim_eligible and (p_line_type<>'clinical' or p_code_system<>'SAMA_CCSA' or coalesce(cardinality(p_diagnosis_codes),0)=0) then raise exception 'Claim-eligible quote lines require clinical SAMA CCSA coding and diagnosis codes'; end if;
  if p_claim_eligible and not exists(
    select 1 from public.billing_code_reference r join public.source_dataset_release sr on sr.id=r.source_release_id join public.source_dataset d on d.id=sr.dataset_id
    where r.code_system='SAMA_CCSA' and r.code=p_code and r.active and sr.status='active' and d.licence_required
  ) then raise exception 'Claim-eligible CCSA code is not backed by an active licensed source'; end if;
  select * into v_profile from public.practice_billing_profile where practice_id=v_quote.practice_id;
  v_tax_rate:=case when coalesce(v_profile.vat_registered,false) then coalesce(p_tax_rate,v_profile.default_tax_rate,0) else 0 end;
  if not coalesce(v_profile.vat_registered,false) and coalesce(p_tax_rate,0)<>0 then raise exception 'This practice is not configured as VAT registered'; end if;
  v_base:=round(p_quantity*p_unit_amount,2); v_tax:=round(v_base*v_tax_rate,2); v_total:=v_base+v_tax;
  select coalesce(max(line_no),0)+1 into v_line_no from public.billing_quote_line where quote_id=p_quote_id;
  insert into public.billing_quote_line(quote_id,line_no,line_type,code_system,code,description,modifier_codes,diagnosis_codes,quantity,unit_amount,tax_rate,tax_amount,line_amount,claim_eligible)
  values(p_quote_id,v_line_no,p_line_type,case when p_line_type='transactional' then coalesce(p_code_system,'PRACTICE_CUSTOM') else p_code_system end,case when p_line_type='transactional' then coalesce(p_code,'CUSTOM') else p_code end,trim(p_description),coalesce(p_modifier_codes,'{}'),coalesce(p_diagnosis_codes,'{}'),p_quantity,p_unit_amount,v_tax_rate,v_tax,v_total,p_claim_eligible)
  returning id into v_id;
  update public.billing_quote set subtotal_amount=subtotal_amount+v_base,tax_amount=tax_amount+v_tax,total_amount=total_amount+v_total,updated_at=now() where id=p_quote_id;
  insert into public.billing_quote_event(quote_id,event_type,actor_user_id,metadata) values(p_quote_id,'line_added',v_user,jsonb_build_object('line_id',v_id,'line_no',v_line_no,'amount',v_total));
  return v_id;
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
  update public.billing_quote set status=p_status,sent_at=case when p_status='sent' then now() else sent_at end,
    accepted_at=case when p_status='accepted' then now() else accepted_at end,rejected_at=case when p_status='rejected' then now() else rejected_at end,updated_at=now()
  where id=p_quote_id;
  insert into public.billing_quote_event(quote_id,event_type,actor_user_id,metadata) values(p_quote_id,p_status,v_user,jsonb_build_object('previous_status',v_quote.status));
  return p_quote_id;
end; $$;

create or replace function public.create_revenue_invoice(
  p_practice_id uuid,p_account_id uuid,p_invoice_kind text,p_patient_id uuid default null,p_encounter_id uuid default null,
  p_invoice_date date default current_date,p_due_date date default null,p_reference text default null,p_notes text default null,p_terms text default null
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_account public.billing_account%rowtype; v_id uuid := gen_random_uuid(); v_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_invoice_kind not in ('clinical','transactional','mixed') then raise exception 'Invalid invoice kind'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select * into v_account from public.billing_account where id=p_account_id and practice_id=p_practice_id and status='active';
  if not found then raise exception 'Active billing account required'; end if;
  if p_patient_id is not null and not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then raise exception 'Patient is not in selected practice'; end if;
  if p_encounter_id is not null and not exists(select 1 from public.practice_encounter e where e.id=p_encounter_id and e.practice_id=p_practice_id and (p_patient_id is null or e.patient_id=p_patient_id)) then raise exception 'Encounter does not belong to this practice/patient'; end if;
  if p_invoice_kind='clinical' and p_patient_id is null then raise exception 'Clinical invoices require a patient'; end if;
  v_number:=public.next_billing_document_number(p_practice_id,'invoice',coalesce(p_invoice_date,current_date));
  insert into public.billing_invoice(id,practice_id,account_id,patient_id,encounter_id,invoice_number,invoice_date,due_date,invoice_kind,status,total_amount,subtotal_amount,tax_amount,scheme_portion,patient_portion,received_amount,balance_amount,reference,notes,terms,supplier_snapshot,recipient_snapshot,source_system,created_by)
  values(v_id,p_practice_id,p_account_id,p_patient_id,p_encounter_id,v_number,coalesce(p_invoice_date,current_date),coalesce(p_due_date,coalesce(p_invoice_date,current_date)+v_account.payment_terms_days),p_invoice_kind,'draft',0,0,0,0,0,0,0,nullif(trim(coalesce(p_reference,'')),''),nullif(trim(coalesce(p_notes,'')),''),nullif(trim(coalesce(p_terms,'')),''),public.billing_supplier_snapshot(p_practice_id),public.billing_recipient_snapshot(p_account_id),'PracticeCtrl',v_user);
  insert into public.billing_invoice_liability(practice_id,invoice_id,account_id,liability_type,amount)
  values(p_practice_id,v_id,p_account_id,case when v_account.account_type='patient' then 'patient' when v_account.account_type='medical_scheme' then 'scheme' else 'other' end,0);
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata) values(v_id,'created',v_user,jsonb_build_object('invoice_number',v_number,'invoice_kind',p_invoice_kind,'account_id',p_account_id));
  return v_id;
end; $$;

create or replace function public.add_revenue_invoice_line(
  p_invoice_id uuid,p_line_type text,p_description text,p_quantity numeric,p_unit_amount numeric,p_service_date date default null,
  p_code_system text default null,p_code text default null,p_modifier_codes text[] default '{}',p_diagnosis_codes text[] default '{}',
  p_tax_rate numeric default null,p_claim_eligible boolean default false
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_invoice public.billing_invoice%rowtype; v_profile public.practice_billing_profile%rowtype;
  v_line_no integer; v_id uuid; v_base numeric(14,2); v_tax_rate numeric(7,6); v_tax numeric(14,2); v_total numeric(14,2); v_liability_count integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_line_type not in ('clinical','transactional') then raise exception 'Invalid invoice line type'; end if;
  if length(trim(coalesce(p_description,'')))<2 then raise exception 'Description is required'; end if;
  if coalesce(p_quantity,0)<=0 or coalesce(p_unit_amount,-1)<0 then raise exception 'Quantity and unit amount are invalid'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if v_invoice.status<>'draft' then raise exception 'Only draft invoices can be edited'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  if p_line_type='clinical' and v_invoice.patient_id is null then raise exception 'Clinical invoice lines require a patient-linked invoice'; end if;
  if p_claim_eligible and (p_line_type<>'clinical' or p_code_system<>'SAMA_CCSA' or coalesce(cardinality(p_diagnosis_codes),0)=0) then raise exception 'Claim-eligible invoice lines require SAMA CCSA procedure coding and diagnosis codes'; end if;
  if p_claim_eligible and not exists(
    select 1 from public.billing_code_reference r join public.source_dataset_release sr on sr.id=r.source_release_id join public.source_dataset d on d.id=sr.dataset_id
    where r.code_system='SAMA_CCSA' and r.code=p_code and r.active and sr.status='active' and d.licence_required
  ) then raise exception 'Claim-eligible CCSA code is not backed by an active licensed source'; end if;
  select * into v_profile from public.practice_billing_profile where practice_id=v_invoice.practice_id;
  v_tax_rate:=case when coalesce(v_profile.vat_registered,false) then coalesce(p_tax_rate,v_profile.default_tax_rate,0) else 0 end;
  if not coalesce(v_profile.vat_registered,false) and coalesce(p_tax_rate,0)<>0 then raise exception 'This practice is not configured as VAT registered'; end if;
  v_base:=round(p_quantity*p_unit_amount,2); v_tax:=round(v_base*v_tax_rate,2); v_total:=v_base+v_tax;
  select coalesce(max(line_no),0)+1 into v_line_no from public.billing_invoice_line where invoice_id=p_invoice_id;
  insert into public.billing_invoice_line(invoice_id,line_no,line_type,service_date,code_system,code,description_snapshot,modifier_codes,diagnosis_codes,quantity,unit_amount,tax_rate,tax_amount,line_amount,patient_portion,scheme_portion,claim_eligible,metadata)
  values(p_invoice_id,v_line_no,p_line_type,coalesce(p_service_date,v_invoice.invoice_date),case when p_line_type='transactional' then coalesce(p_code_system,'PRACTICE_CUSTOM') else p_code_system end,case when p_line_type='transactional' then coalesce(p_code,'CUSTOM') else p_code end,trim(p_description),coalesce(p_modifier_codes,'{}'),coalesce(p_diagnosis_codes,'{}'),p_quantity,p_unit_amount,v_tax_rate,v_tax,v_total,0,0,p_claim_eligible,jsonb_build_object('claim_eligible',p_claim_eligible,'source','PracticeCtrl revenue engine'))
  returning id into v_id;
  update public.billing_invoice set subtotal_amount=subtotal_amount+v_base,tax_amount=tax_amount+v_tax,total_amount=total_amount+v_total,balance_amount=greatest((total_amount+v_total)-credited_amount-received_amount,0),updated_at=now() where id=p_invoice_id;
  select count(*) into v_liability_count from public.billing_invoice_liability where invoice_id=p_invoice_id;
  if v_liability_count=1 then update public.billing_invoice_liability set amount=(select total_amount from public.billing_invoice where id=p_invoice_id) where invoice_id=p_invoice_id; end if;
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata) values(p_invoice_id,'line_added',v_user,jsonb_build_object('line_id',v_id,'line_no',v_line_no,'amount',v_total,'claim_eligible',p_claim_eligible));
  return v_id;
end; $$;

create or replace function public.set_billing_invoice_liability(p_invoice_id uuid,p_account_id uuid,p_liability_type text,p_amount numeric)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid := (select auth.uid()); v_invoice public.billing_invoice%rowtype; v_id uuid; v_sum numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_liability_type not in ('patient','scheme','other') then raise exception 'Invalid liability type'; end if;
  if coalesce(p_amount,-1)<0 then raise exception 'Liability amount cannot be negative'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found or v_invoice.status<>'draft' then raise exception 'Draft invoice required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  if not exists(select 1 from public.billing_account a where a.id=p_account_id and a.practice_id=v_invoice.practice_id and a.status='active') then raise exception 'Active billing account required'; end if;
  if p_amount=0 then delete from public.billing_invoice_liability where invoice_id=p_invoice_id and account_id=p_account_id and liability_type=p_liability_type; v_id:=null;
  else
    insert into public.billing_invoice_liability(practice_id,invoice_id,account_id,liability_type,amount)
    values(v_invoice.practice_id,p_invoice_id,p_account_id,p_liability_type,p_amount)
    on conflict(invoice_id,account_id,liability_type) do update set amount=excluded.amount returning id into v_id;
  end if;
  select coalesce(sum(amount),0) into v_sum from public.billing_invoice_liability where invoice_id=p_invoice_id;
  if v_sum>v_invoice.total_amount then raise exception 'Liability split exceeds invoice total'; end if;
  update public.billing_invoice set
    patient_portion=coalesce((select sum(amount) from public.billing_invoice_liability where invoice_id=p_invoice_id and liability_type='patient'),0),
    scheme_portion=coalesce((select sum(amount) from public.billing_invoice_liability where invoice_id=p_invoice_id and liability_type='scheme'),0),updated_at=now()
  where id=p_invoice_id;
  return v_id;
end; $$;

create or replace function public.guard_billing_invoice_lifecycle()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
  if old.status<>'draft' and (
    old.practice_id is distinct from new.practice_id or old.account_id is distinct from new.account_id or old.patient_id is distinct from new.patient_id or
    old.encounter_id is distinct from new.encounter_id or old.invoice_number is distinct from new.invoice_number or old.invoice_date is distinct from new.invoice_date or
    old.total_amount is distinct from new.total_amount or old.subtotal_amount is distinct from new.subtotal_amount or old.tax_amount is distinct from new.tax_amount or
    old.credited_amount is distinct from new.credited_amount or old.supplier_snapshot is distinct from new.supplier_snapshot or old.recipient_snapshot is distinct from new.recipient_snapshot
  ) and coalesce(current_setting('practicectrl.billing_posting',true),'')<>'on' then raise exception 'Finalised invoice financial/provenance fields are immutable'; end if;
  if old.status='draft' and new.status<>'draft' and coalesce(current_setting('practicectrl.billing_posting',true),'')<>'on' then raise exception 'Invoice finalisation must use the governed billing action'; end if;
  return new;
end; $$;

drop trigger if exists trg_guard_billing_invoice_lifecycle on public.billing_invoice;
create trigger trg_guard_billing_invoice_lifecycle before update on public.billing_invoice for each row execute function public.guard_billing_invoice_lifecycle();

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
  return p_invoice_id;
end; $$;

revoke all on function public.billing_supplier_snapshot(uuid) from public,anon;
revoke all on function public.billing_recipient_snapshot(uuid) from public,anon;
revoke all on function public.next_billing_document_number(uuid,text,date) from public,anon;
revoke all on function public.ensure_patient_billing_account(uuid,uuid) from public,anon;
revoke all on function public.create_billing_account(uuid,text,text,text,uuid,uuid,text,text,integer) from public,anon;
revoke all on function public.create_revenue_quote(uuid,uuid,uuid,uuid,date,date,text,text,text) from public,anon;
revoke all on function public.add_billing_quote_line(uuid,text,text,numeric,numeric,text,text,text[],text[],numeric,boolean) from public,anon;
revoke all on function public.set_billing_quote_status(uuid,text) from public,anon;
revoke all on function public.create_revenue_invoice(uuid,uuid,text,uuid,uuid,date,date,text,text,text) from public,anon;
revoke all on function public.add_revenue_invoice_line(uuid,text,text,numeric,numeric,date,text,text,text[],text[],numeric,boolean) from public,anon;
revoke all on function public.set_billing_invoice_liability(uuid,uuid,text,numeric) from public,anon;

grant execute on function public.billing_supplier_snapshot(uuid) to authenticated;
grant execute on function public.billing_recipient_snapshot(uuid) to authenticated;
grant execute on function public.next_billing_document_number(uuid,text,date) to authenticated;
grant execute on function public.ensure_patient_billing_account(uuid,uuid) to authenticated;
grant execute on function public.create_billing_account(uuid,text,text,text,uuid,uuid,text,text,integer) to authenticated;
grant execute on function public.create_revenue_quote(uuid,uuid,uuid,uuid,date,date,text,text,text) to authenticated;
grant execute on function public.add_billing_quote_line(uuid,text,text,numeric,numeric,text,text,text[],text[],numeric,boolean) to authenticated;
grant execute on function public.set_billing_quote_status(uuid,text) to authenticated;
grant execute on function public.create_revenue_invoice(uuid,uuid,text,uuid,uuid,date,date,text,text,text) to authenticated;
grant execute on function public.add_revenue_invoice_line(uuid,text,text,numeric,numeric,date,text,text,text[],text[],numeric,boolean) to authenticated;
grant execute on function public.set_billing_invoice_liability(uuid,uuid,text,numeric) to authenticated;
