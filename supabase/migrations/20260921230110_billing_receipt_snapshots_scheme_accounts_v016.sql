
alter table public.billing_payment_receipt
  add column supplier_snapshot jsonb not null default '{}'::jsonb,
  add column recipient_snapshot jsonb not null default '{}'::jsonb;

update public.billing_payment_receipt r
set supplier_snapshot=public.billing_supplier_snapshot(r.practice_id),
    recipient_snapshot=case when r.account_id is null then '{}'::jsonb else public.billing_recipient_snapshot(r.account_id) end
where supplier_snapshot='{}'::jsonb or recipient_snapshot='{}'::jsonb;

create or replace function public.ensure_medical_scheme_billing_account(p_practice_id uuid,p_medical_scheme_id uuid)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_scheme public.medical_scheme%rowtype;
  v_id uuid;
  v_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;
  select * into v_scheme from public.medical_scheme where id=p_medical_scheme_id and regulatory_status='active';
  if not found then raise exception 'Active medical scheme not found'; end if;
  select id into v_id from public.billing_account where practice_id=p_practice_id and medical_scheme_id=p_medical_scheme_id and account_type='medical_scheme' limit 1;
  if v_id is not null then return v_id; end if;
  v_number:='SCH-'||upper(substr(coalesce(nullif(regexp_replace(coalesce(v_scheme.cms_registration_number,''),'[^A-Za-z0-9]','','g'),''),replace(v_scheme.id::text,'-','')),1,12));
  insert into public.billing_account(practice_id,account_number,account_type,medical_scheme_id,display_name,created_by,updated_by)
  values(p_practice_id,v_number,'medical_scheme',p_medical_scheme_id,v_scheme.name,v_user,v_user)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.create_revenue_receipt(
  p_practice_id uuid,p_account_id uuid,p_receipt_date date,p_amount numeric,p_payment_method text default null,
  p_external_reference text default null,p_patient_id uuid default null
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
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
  insert into public.billing_payment_receipt(
    id,practice_id,account_id,patient_id,medical_scheme_id,payer_type,receipt_number,receipt_date,amount,payment_method,
    external_reference,source_system,created_by,supplier_snapshot,recipient_snapshot
  )
  values(
    v_id,p_practice_id,p_account_id,coalesce(p_patient_id,v_account.patient_id),v_account.medical_scheme_id,
    case when v_account.account_type='patient' then 'patient' when v_account.account_type='medical_scheme' then 'scheme' when v_account.account_type='insurer' then 'insurer' else 'other' end,
    v_number,coalesce(p_receipt_date,current_date),p_amount,nullif(trim(coalesce(p_payment_method,'')),''),
    nullif(trim(coalesce(p_external_reference,'')),''),'PracticeCtrl',v_user,
    public.billing_supplier_snapshot(p_practice_id),public.billing_recipient_snapshot(p_account_id)
  );
  perform set_config('practicectrl.billing_posting','on',true);
  insert into public.billing_ledger_entry(practice_id,account_id,transaction_date,entry_type,document_number,description,signed_amount,receipt_id,source_key,created_by,metadata)
  values(p_practice_id,p_account_id,coalesce(p_receipt_date,current_date),'receipt_allocation',v_number,'Receipt '||v_number,-p_amount,v_id,'receipt:'||v_id::text,v_user,jsonb_build_object('payment_method',p_payment_method,'external_reference',p_external_reference));
  perform set_config('practicectrl.billing_posting','off',true);
  return v_id;
end;
$$;

revoke all on function public.ensure_medical_scheme_billing_account(uuid,uuid) from public,anon;
grant execute on function public.ensure_medical_scheme_billing_account(uuid,uuid) to authenticated;

