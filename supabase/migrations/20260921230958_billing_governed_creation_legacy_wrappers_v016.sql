
drop policy if exists billing_invoice_line_finance_delete on public.billing_invoice_line;
create policy billing_invoice_line_finance_delete on public.billing_invoice_line for delete to authenticated using (
  (select current_setting('practicectrl.billing_line_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id
    where i.id=billing_invoice_line.invoice_id and i.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin'))
);

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
  perform set_config('practicectrl.billing_document_creation','on',true);
  insert into public.billing_quote(id,practice_id,account_id,patient_id,encounter_id,quote_number,quote_date,valid_until,reference,notes,terms,supplier_snapshot,recipient_snapshot,created_by)
  values(v_id,p_practice_id,p_account_id,p_patient_id,p_encounter_id,v_number,coalesce(p_quote_date,current_date),coalesce(p_valid_until,coalesce(p_quote_date,current_date)+30),nullif(trim(coalesce(p_reference,'')),''),nullif(trim(coalesce(p_notes,'')),''),nullif(trim(coalesce(p_terms,'')),''),public.billing_supplier_snapshot(p_practice_id),public.billing_recipient_snapshot(p_account_id),v_user);
  perform set_config('practicectrl.billing_document_creation','off',true);
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
  if not found or v_quote.status<>'draft' then raise exception 'Draft quote required'; end if;
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
  perform set_config('practicectrl.billing_line_mutation','on',true);
  insert into public.billing_quote_line(quote_id,line_no,line_type,code_system,code,description,modifier_codes,diagnosis_codes,quantity,unit_amount,tax_rate,tax_amount,line_amount,claim_eligible)
  values(p_quote_id,v_line_no,p_line_type,case when p_line_type='transactional' then coalesce(p_code_system,'PRACTICE_CUSTOM') else p_code_system end,case when p_line_type='transactional' then coalesce(p_code,'CUSTOM') else p_code end,trim(p_description),coalesce(p_modifier_codes,'{}'),coalesce(p_diagnosis_codes,'{}'),p_quantity,p_unit_amount,v_tax_rate,v_tax,v_total,p_claim_eligible)
  returning id into v_id;
  perform set_config('practicectrl.billing_line_mutation','off',true);
  update public.billing_quote set subtotal_amount=subtotal_amount+v_base,tax_amount=tax_amount+v_tax,total_amount=total_amount+v_total,updated_at=now() where id=p_quote_id;
  insert into public.billing_quote_event(quote_id,event_type,actor_user_id,metadata) values(p_quote_id,'line_added',v_user,jsonb_build_object('line_id',v_id,'line_no',v_line_no,'amount',v_total));
  return v_id;
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
  perform set_config('practicectrl.billing_document_creation','on',true);
  insert into public.billing_invoice(id,practice_id,account_id,patient_id,encounter_id,invoice_number,invoice_date,due_date,invoice_kind,status,total_amount,subtotal_amount,tax_amount,scheme_portion,patient_portion,received_amount,balance_amount,reference,notes,terms,supplier_snapshot,recipient_snapshot,source_system,created_by)
  values(v_id,p_practice_id,p_account_id,p_patient_id,p_encounter_id,v_number,coalesce(p_invoice_date,current_date),coalesce(p_due_date,coalesce(p_invoice_date,current_date)+v_account.payment_terms_days),p_invoice_kind,'draft',0,0,0,0,0,0,0,nullif(trim(coalesce(p_reference,'')),''),nullif(trim(coalesce(p_notes,'')),''),nullif(trim(coalesce(p_terms,'')),''),public.billing_supplier_snapshot(p_practice_id),public.billing_recipient_snapshot(p_account_id),'PracticeCtrl',v_user);
  perform set_config('practicectrl.billing_document_creation','off',true);
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
  v_line_no integer; v_id uuid; v_base numeric(14,2); v_tax_rate numeric(7,6); v_tax numeric(14,2); v_total numeric(14,2);
  v_liability_count integer; v_diagnoses text[] := coalesce(p_diagnosis_codes,'{}'::text[]);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_line_type not in ('clinical','transactional') then raise exception 'Invalid invoice line type'; end if;
  if length(trim(coalesce(p_description,'')))<2 then raise exception 'Description is required'; end if;
  if coalesce(p_quantity,0)<=0 or coalesce(p_unit_amount,-1)<0 then raise exception 'Quantity and unit amount are invalid'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found or v_invoice.status<>'draft' then raise exception 'Draft invoice required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  if p_line_type='clinical' and v_invoice.patient_id is null then raise exception 'Clinical invoice lines require a patient-linked invoice'; end if;
  if p_line_type='clinical' and coalesce(cardinality(v_diagnoses),0)=0 and v_invoice.encounter_id is not null then
    select coalesce(array_agg(distinct c.code order by c.code),'{}'::text[]) into v_diagnoses
    from public.coding_session s join public.coding_decision d on d.coding_session_id=s.id join public.sa_icd10_code c on c.id=d.code_id
    where s.practice_id=v_invoice.practice_id and s.encounter_id=v_invoice.encounter_id and d.decision in ('ACCEPTED','MANUALLY_SELECTED');
  end if;
  if p_claim_eligible and (p_line_type<>'clinical' or p_code_system<>'SAMA_CCSA' or coalesce(cardinality(v_diagnoses),0)=0) then raise exception 'Claim-eligible invoice lines require SAMA CCSA procedure coding and diagnosis codes'; end if;
  if p_claim_eligible and not exists(
    select 1 from public.billing_code_reference r join public.source_dataset_release sr on sr.id=r.source_release_id join public.source_dataset d on d.id=sr.dataset_id
    where r.code_system='SAMA_CCSA' and r.code=p_code and r.active and sr.status='active' and d.licence_required
  ) then raise exception 'Claim-eligible CCSA code is not backed by an active licensed source'; end if;
  select * into v_profile from public.practice_billing_profile where practice_id=v_invoice.practice_id;
  v_tax_rate:=case when coalesce(v_profile.vat_registered,false) then coalesce(p_tax_rate,v_profile.default_tax_rate,0) else 0 end;
  if not coalesce(v_profile.vat_registered,false) and coalesce(p_tax_rate,0)<>0 then raise exception 'This practice is not configured as VAT registered'; end if;
  v_base:=round(p_quantity*p_unit_amount,2); v_tax:=round(v_base*v_tax_rate,2); v_total:=v_base+v_tax;
  select coalesce(max(line_no),0)+1 into v_line_no from public.billing_invoice_line where invoice_id=p_invoice_id;
  perform set_config('practicectrl.billing_line_mutation','on',true);
  insert into public.billing_invoice_line(invoice_id,line_no,line_type,service_date,code_system,code,description_snapshot,modifier_codes,diagnosis_codes,quantity,unit_amount,tax_rate,tax_amount,line_amount,patient_portion,scheme_portion,claim_eligible,metadata)
  values(p_invoice_id,v_line_no,p_line_type,coalesce(p_service_date,v_invoice.invoice_date),case when p_line_type='transactional' then coalesce(p_code_system,'PRACTICE_CUSTOM') else coalesce(p_code_system,'PRACTICE_CUSTOM') end,case when p_line_type='transactional' then coalesce(p_code,'CUSTOM') else coalesce(p_code,'CLINICAL') end,trim(p_description),coalesce(p_modifier_codes,'{}'),v_diagnoses,p_quantity,p_unit_amount,v_tax_rate,v_tax,v_total,0,0,p_claim_eligible,jsonb_build_object('claim_eligible',p_claim_eligible,'source','PracticeCtrl revenue engine','diagnosis_source',case when p_line_type='clinical' and coalesce(cardinality(p_diagnosis_codes),0)=0 and coalesce(cardinality(v_diagnoses),0)>0 then 'Code10 encounter decisions' else 'user supplied' end))
  returning id into v_id;
  perform set_config('practicectrl.billing_line_mutation','off',true);
  update public.billing_invoice set subtotal_amount=subtotal_amount+v_base,tax_amount=tax_amount+v_tax,total_amount=total_amount+v_total,balance_amount=greatest((total_amount+v_total)-credited_amount-received_amount,0),updated_at=now() where id=p_invoice_id;
  select count(*) into v_liability_count from public.billing_invoice_liability where invoice_id=p_invoice_id;
  if v_liability_count=1 then update public.billing_invoice_liability set amount=(select total_amount from public.billing_invoice where id=p_invoice_id) where invoice_id=p_invoice_id; end if;
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata) values(p_invoice_id,'line_added',v_user,jsonb_build_object('line_id',v_id,'line_no',v_line_no,'amount',v_total,'claim_eligible',p_claim_eligible,'diagnosis_codes',v_diagnoses));
  return v_id;
end; $$;

create or replace function public.remove_revenue_invoice_line(p_invoice_line_id uuid,p_reason text)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_line public.billing_invoice_line%rowtype; v_invoice public.billing_invoice%rowtype;
  v_subtotal numeric(14,2); v_tax numeric(14,2); v_total numeric(14,2); v_liability_count integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Removal reason is required'; end if;
  select * into v_line from public.billing_invoice_line where id=p_invoice_line_id for update;
  if not found then raise exception 'Invoice line not found or not accessible'; end if;
  select * into v_invoice from public.billing_invoice where id=v_line.invoice_id for update;
  if v_invoice.status<>'draft' then raise exception 'Lines can be removed only while the invoice is draft'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  perform set_config('practicectrl.billing_line_mutation','on',true);
  delete from public.billing_invoice_line where id=p_invoice_line_id;
  perform set_config('practicectrl.billing_line_mutation','off',true);
  select coalesce(sum(line_amount-tax_amount),0),coalesce(sum(tax_amount),0),coalesce(sum(line_amount),0)
    into v_subtotal,v_tax,v_total from public.billing_invoice_line where invoice_id=v_invoice.id;
  update public.billing_invoice set subtotal_amount=v_subtotal,tax_amount=v_tax,total_amount=v_total,balance_amount=greatest(v_total-credited_amount-received_amount,0),updated_at=now() where id=v_invoice.id;
  select count(*) into v_liability_count from public.billing_invoice_liability where invoice_id=v_invoice.id;
  if v_liability_count=1 then update public.billing_invoice_liability set amount=v_total where invoice_id=v_invoice.id; end if;
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(v_invoice.id,'line_removed',v_user,jsonb_build_object('invoice_line_id',p_invoice_line_id,'line_no',v_line.line_no,'amount',v_line.line_amount,'reason',trim(p_reason)));
  return p_invoice_line_id;
end; $$;

create or replace function public.create_billing_credit_note(p_invoice_id uuid,p_account_id uuid,p_reason text,p_description text,p_amount numeric,p_tax_amount numeric default 0,p_credit_note_date date default current_date)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_invoice public.billing_invoice%rowtype; v_id uuid := gen_random_uuid(); v_number text;
  v_base numeric(14,2); v_existing numeric(14,2); v_liability numeric(14,2); v_allocated numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_reason,'')))<3 or length(trim(coalesce(p_description,'')))<2 then raise exception 'Credit reason and description are required'; end if;
  if coalesce(p_amount,0)<=0 or coalesce(p_tax_amount,0)<0 or p_tax_amount>p_amount then raise exception 'Invalid credit amount'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id;
  if not found or v_invoice.status in ('draft','void') then raise exception 'A finalised invoice is required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select amount into v_liability from public.billing_invoice_liability where invoice_id=p_invoice_id and account_id=p_account_id;
  if v_liability is null then raise exception 'Account is not a liable party on this invoice'; end if;
  select coalesce(sum(total_amount),0) into v_existing from public.billing_credit_note where invoice_id=p_invoice_id and account_id=p_account_id and status='final';
  select coalesce(sum(a.amount),0) into v_allocated from public.billing_payment_allocation a
    join public.billing_payment_receipt r on r.id=a.receipt_id
    where a.invoice_id=p_invoice_id and a.allocation_status='posted' and r.account_id=p_account_id;
  if round(v_existing+v_allocated+p_amount,2)>round(v_liability,2) then raise exception 'Credit plus allocated payments cannot exceed this account liability'; end if;
  v_number:=public.next_billing_document_number(v_invoice.practice_id,'credit_note',coalesce(p_credit_note_date,current_date)); v_base:=p_amount-coalesce(p_tax_amount,0);
  perform set_config('practicectrl.billing_document_creation','on',true);
  insert into public.billing_credit_note(id,practice_id,account_id,invoice_id,credit_note_number,credit_note_date,status,currency,subtotal_amount,tax_amount,total_amount,reason,supplier_snapshot,recipient_snapshot,created_by)
  values(v_id,v_invoice.practice_id,p_account_id,p_invoice_id,v_number,coalesce(p_credit_note_date,current_date),'draft',v_invoice.currency,v_base,coalesce(p_tax_amount,0),p_amount,trim(p_reason),public.billing_supplier_snapshot(v_invoice.practice_id),public.billing_recipient_snapshot(p_account_id),v_user);
  perform set_config('practicectrl.billing_document_creation','off',true);
  perform set_config('practicectrl.billing_line_mutation','on',true);
  insert into public.billing_credit_note_line(credit_note_id,line_no,description,quantity,unit_amount,tax_rate,tax_amount,line_amount)
  values(v_id,1,trim(p_description),1,v_base,case when v_base=0 then 0 else coalesce(p_tax_amount,0)/v_base end,coalesce(p_tax_amount,0),p_amount);
  perform set_config('practicectrl.billing_line_mutation','off',true);
  insert into public.billing_credit_note_event(credit_note_id,event_type,actor_user_id,metadata)
  values(v_id,'created',v_user,jsonb_build_object('invoice_id',p_invoice_id,'credit_note_number',v_number,'amount',p_amount));
  return v_id;
end; $$;

create or replace function public.finalise_billing_credit_note(p_credit_note_id uuid)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_user uuid := (select auth.uid()); v_credit public.billing_credit_note%rowtype; v_invoice public.billing_invoice%rowtype;
  v_line_total numeric(14,2); v_line_tax numeric(14,2); v_liability numeric(14,2); v_existing numeric(14,2); v_allocated numeric(14,2);
  v_new_credit numeric(14,2); v_new_balance numeric(14,2);
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
  select coalesce(sum(a.amount),0) into v_allocated from public.billing_payment_allocation a
    join public.billing_payment_receipt r on r.id=a.receipt_id
    where a.invoice_id=v_credit.invoice_id and a.allocation_status='posted' and r.account_id=v_credit.account_id;
  if v_liability is null or round(v_existing+v_allocated+v_credit.total_amount,2)>round(v_liability,2) then raise exception 'Credit plus allocated payments exceeds account liability on source invoice'; end if;
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
  perform set_config('practicectrl.billing_document_creation','on',true);
  insert into public.billing_payment_receipt(id,practice_id,account_id,patient_id,medical_scheme_id,payer_type,receipt_number,receipt_date,amount,payment_method,external_reference,source_system,created_by,supplier_snapshot,recipient_snapshot)
  values(v_id,p_practice_id,p_account_id,coalesce(p_patient_id,v_account.patient_id),v_account.medical_scheme_id,case when v_account.account_type='patient' then 'patient' when v_account.account_type='medical_scheme' then 'scheme' when v_account.account_type='insurer' then 'insurer' else 'other' end,v_number,coalesce(p_receipt_date,current_date),p_amount,nullif(trim(coalesce(p_payment_method,'')),''),nullif(trim(coalesce(p_external_reference,'')),''),'PracticeCtrl',v_user,public.billing_supplier_snapshot(p_practice_id),public.billing_recipient_snapshot(p_account_id));
  perform set_config('practicectrl.billing_document_creation','off',true);
  perform set_config('practicectrl.billing_posting','on',true);
  insert into public.billing_ledger_entry(practice_id,account_id,transaction_date,entry_type,document_number,description,signed_amount,receipt_id,source_key,created_by,metadata)
  values(p_practice_id,p_account_id,coalesce(p_receipt_date,current_date),'receipt',v_number,'Receipt '||v_number,-p_amount,v_id,'receipt:'||v_id::text,v_user,jsonb_build_object('payment_method',p_payment_method,'external_reference',p_external_reference));
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
  if v_invoice.status in ('draft','void') then raise exception 'Receipt can only be allocated to a finalised invoice'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  v_account:=v_receipt.account_id;
  if v_account is null then
    select account_id into v_account from public.billing_invoice_liability where invoice_id=p_invoice_id limit 2;
    if (select count(*) from public.billing_invoice_liability where invoice_id=p_invoice_id)<>1 then raise exception 'Receipt account is required for a split-liability invoice'; end if;
    update public.billing_payment_receipt set account_id=v_account,recipient_snapshot=public.billing_recipient_snapshot(v_account) where id=p_receipt_id;
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
  perform set_config('practicectrl.billing_allocation','on',true);
  insert into public.billing_payment_allocation(receipt_id,invoice_id,claim_id,amount,allocation_status,allocated_by,notes)
  values(p_receipt_id,p_invoice_id,p_claim_id,p_amount,'posted',v_user,p_note) returning id into v_allocation_id;
  perform set_config('practicectrl.billing_allocation','off',true);
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
  perform set_config('practicectrl.billing_allocation','on',true);
  update public.billing_payment_allocation set allocation_status='reversed' where id=p_allocation_id;
  perform set_config('practicectrl.billing_allocation','off',true);
  v_new_received:=greatest(v_invoice.received_amount-v_alloc.amount,0); v_new_balance:=greatest(v_invoice.total_amount-v_invoice.credited_amount-v_new_received,0);
  perform set_config('practicectrl.billing_posting','on',true);
  update public.billing_invoice set received_amount=v_new_received,balance_amount=v_new_balance,status=case when v_new_balance=0 then 'paid' when v_new_received>0 then 'part_paid' else 'final' end,updated_at=now() where id=v_invoice.id;
  insert into public.billing_allocation_event(allocation_id,event_type,actor_user_id,reason,metadata) values(p_allocation_id,'reversed',v_user,trim(p_reason),jsonb_build_object('invoice_id',v_invoice.id,'amount',v_alloc.amount,'new_balance',v_new_balance));
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata) values(v_invoice.id,'allocation_reversed',v_user,jsonb_build_object('allocation_id',p_allocation_id,'amount',v_alloc.amount,'reason',trim(p_reason),'new_balance',v_new_balance));
  perform set_config('practicectrl.billing_posting','off',true);
  return p_allocation_id;
end; $$;

-- Legacy compatibility wrappers now use the same revenue engine.
create or replace function public.create_practice_custom_invoice(
  p_practice_id uuid,p_patient_id uuid,p_invoice_date date,p_description text,p_amount numeric,
  p_patient_portion numeric default null,p_scheme_portion numeric default null
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
  v_invoice uuid; v_patient_account uuid; v_scheme_account uuid; v_membership public.crm_patient_scheme_membership%rowtype;
  v_patient_amount numeric(14,2):=coalesce(p_patient_portion,p_amount); v_scheme_amount numeric(14,2):=coalesce(p_scheme_portion,0);
begin
  if p_patient_id is null then raise exception 'Patient is required for the legacy custom-invoice action; use the Revenue workspace for non-patient debtors'; end if;
  if round(v_patient_amount+v_scheme_amount,2)<>round(p_amount,2) then raise exception 'Patient and scheme portions must equal invoice total'; end if;
  v_patient_account:=public.ensure_patient_billing_account(p_practice_id,p_patient_id);
  v_invoice:=public.create_revenue_invoice(p_practice_id,v_patient_account,'transactional',p_patient_id,null,coalesce(p_invoice_date,current_date),null,null,null,null);
  perform public.add_revenue_invoice_line(v_invoice,'transactional',p_description,1,p_amount,coalesce(p_invoice_date,current_date),'PRACTICE_CUSTOM','CUSTOM','{}','{}',0,false);
  if v_scheme_amount>0 then
    select * into v_membership from public.crm_patient_scheme_membership
    where practice_id=p_practice_id and patient_id=p_patient_id and membership_status='active_verified' and medical_scheme_id is not null
    order by verified_at desc nulls last,updated_at desc limit 1;
    if not found then raise exception 'Verified scheme membership is required for a scheme liability'; end if;
    v_scheme_account:=public.ensure_medical_scheme_billing_account(p_practice_id,v_membership.medical_scheme_id);
    perform public.set_billing_invoice_liability(v_invoice,v_patient_account,'patient',v_patient_amount);
    perform public.set_billing_invoice_liability(v_invoice,v_scheme_account,'scheme',v_scheme_amount);
  end if;
  return v_invoice;
end; $$;

create or replace function public.create_encounter_private_invoice(p_encounter_id uuid,p_description text,p_amount numeric)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid()); v_enc public.practice_encounter%rowtype; v_path text; v_account uuid; v_invoice uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
  if length(trim(coalesce(p_description,'')))<2 then raise exception 'Description is required'; end if;
  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then raise exception 'Encounter not found or not accessible'; end if;
  if v_enc.status<>'completed' then raise exception 'Encounter must be completed before private invoicing'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_enc.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select billing_path into v_path from public.encounter_billing_context where encounter_id=v_enc.id;
  if coalesce(v_path,'unresolved') not in ('private_pay','other') then raise exception 'Encounter billing path must be private_pay or other for a custom non-claimable invoice'; end if;
  if exists(select 1 from public.billing_invoice where encounter_id=v_enc.id and status<>'void') then raise exception 'Encounter already has an active PracticeCtrl invoice'; end if;
  v_account:=public.ensure_patient_billing_account(v_enc.practice_id,v_enc.patient_id);
  v_invoice:=public.create_revenue_invoice(v_enc.practice_id,v_account,'transactional',v_enc.patient_id,v_enc.id,v_enc.service_date,null,null,null,null);
  perform public.add_revenue_invoice_line(v_invoice,'transactional',p_description,1,p_amount,v_enc.service_date,'PRACTICE_CUSTOM','CUSTOM','{}','{}',0,false);
  return v_invoice;
end; $$;

create or replace function public.create_billing_receipt(
  p_practice_id uuid,p_patient_id uuid,p_medical_scheme_id uuid,p_payer_type text,p_receipt_number text,p_receipt_date date,p_amount numeric,
  p_payment_method text default null,p_external_reference text default null
) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_account uuid; v_external text;
begin
  if p_patient_id is not null then v_account:=public.ensure_patient_billing_account(p_practice_id,p_patient_id);
  elsif p_medical_scheme_id is not null then v_account:=public.ensure_medical_scheme_billing_account(p_practice_id,p_medical_scheme_id);
  else raise exception 'Patient or medical scheme is required for the legacy receipt action; use the Revenue workspace for other debtor accounts'; end if;
  v_external:=concat_ws(' | ',nullif(trim(coalesce(p_receipt_number,'')),''),nullif(trim(coalesce(p_external_reference,'')),''));
  return public.create_revenue_receipt(p_practice_id,v_account,coalesce(p_receipt_date,current_date),abs(p_amount),p_payment_method,nullif(v_external,''),p_patient_id);
end; $$;

create or replace function public.add_practice_custom_invoice_line(p_invoice_id uuid,p_description text,p_amount numeric)
returns uuid language sql security invoker set search_path=public,pg_temp as $$
  select public.add_revenue_invoice_line(p_invoice_id,'transactional',p_description,1,p_amount,null,'PRACTICE_CUSTOM','CUSTOM','{}'::text[],'{}'::text[],0,false);
$$;

create or replace function public.remove_practice_custom_invoice_line(p_invoice_line_id uuid,p_reason text)
returns uuid language sql security invoker set search_path=public,pg_temp as $$
  select public.remove_revenue_invoice_line(p_invoice_line_id,p_reason);
$$;

revoke all on function public.remove_revenue_invoice_line(uuid,text) from public,anon;
grant execute on function public.remove_revenue_invoice_line(uuid,text) to authenticated;

