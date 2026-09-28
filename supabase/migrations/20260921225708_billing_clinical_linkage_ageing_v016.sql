
create or replace function public.set_billing_invoice_authorisation(p_invoice_id uuid,p_authorisation_id uuid)
returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_invoice public.billing_invoice%rowtype;
  v_auth public.scheme_authorisation%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found or v_invoice.status<>'draft' then raise exception 'Draft invoice required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;

  if p_authorisation_id is null then
    update public.billing_invoice set scheme_authorisation_id=null,updated_at=now() where id=p_invoice_id;
    return p_invoice_id;
  end if;

  select * into v_auth from public.scheme_authorisation where id=p_authorisation_id;
  if not found or v_auth.practice_id<>v_invoice.practice_id then raise exception 'Authorisation is not in this practice'; end if;
  if v_invoice.patient_id is null or v_auth.patient_id<>v_invoice.patient_id then raise exception 'Authorisation does not belong to this invoice patient'; end if;
  if v_auth.status not in ('approved','partially_approved') or nullif(trim(coalesce(v_auth.authorisation_number,'')),'') is null then raise exception 'Approved authorisation with an authorisation number is required'; end if;
  if v_auth.effective_from is not null and v_auth.effective_from>v_invoice.invoice_date then raise exception 'Authorisation is not yet effective for the invoice date'; end if;
  if v_auth.effective_to is not null and v_auth.effective_to<v_invoice.invoice_date then raise exception 'Authorisation has expired for the invoice date'; end if;

  update public.billing_invoice
  set scheme_authorisation_id=v_auth.id,
      medical_scheme_id=coalesce(v_auth.medical_scheme_id,medical_scheme_id),
      medical_scheme_option_id=coalesce(v_auth.medical_scheme_option_id,medical_scheme_option_id),
      updated_at=now()
  where id=p_invoice_id;

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'adjusted',v_user,jsonb_build_object('authorisation_id',v_auth.id,'authorisation_number',v_auth.authorisation_number,'action','authorisation_linked'));
  return p_invoice_id;
end;
$$;

create or replace function public.add_revenue_invoice_line(
  p_invoice_id uuid,p_line_type text,p_description text,p_quantity numeric,p_unit_amount numeric,p_service_date date default null,
  p_code_system text default null,p_code text default null,p_modifier_codes text[] default '{}',p_diagnosis_codes text[] default '{}',
  p_tax_rate numeric default null,p_claim_eligible boolean default false
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_invoice public.billing_invoice%rowtype;
  v_profile public.practice_billing_profile%rowtype;
  v_line_no integer;
  v_id uuid;
  v_base numeric(14,2);
  v_tax_rate numeric(7,6);
  v_tax numeric(14,2);
  v_total numeric(14,2);
  v_liability_count integer;
  v_diagnoses text[] := coalesce(p_diagnosis_codes,'{}'::text[]);
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

  if p_line_type='clinical' and coalesce(cardinality(v_diagnoses),0)=0 and v_invoice.encounter_id is not null then
    select coalesce(array_agg(distinct c.code order by c.code),'{}'::text[])
    into v_diagnoses
    from public.coding_session s
    join public.coding_decision d on d.coding_session_id=s.id
    join public.sa_icd10_code c on c.id=d.code_id
    where s.practice_id=v_invoice.practice_id
      and s.encounter_id=v_invoice.encounter_id
      and d.decision in ('ACCEPTED','MANUALLY_SELECTED');
  end if;

  if p_claim_eligible and (p_line_type<>'clinical' or p_code_system<>'SAMA_CCSA' or coalesce(cardinality(v_diagnoses),0)=0) then
    raise exception 'Claim-eligible invoice lines require SAMA CCSA procedure coding and diagnosis codes';
  end if;
  if p_claim_eligible and not exists(
    select 1 from public.billing_code_reference r
    join public.source_dataset_release sr on sr.id=r.source_release_id
    join public.source_dataset d on d.id=sr.dataset_id
    where r.code_system='SAMA_CCSA' and r.code=p_code and r.active and sr.status='active' and d.licence_required
  ) then raise exception 'Claim-eligible CCSA code is not backed by an active licensed source'; end if;

  select * into v_profile from public.practice_billing_profile where practice_id=v_invoice.practice_id;
  v_tax_rate:=case when coalesce(v_profile.vat_registered,false) then coalesce(p_tax_rate,v_profile.default_tax_rate,0) else 0 end;
  if not coalesce(v_profile.vat_registered,false) and coalesce(p_tax_rate,0)<>0 then raise exception 'This practice is not configured as VAT registered'; end if;

  v_base:=round(p_quantity*p_unit_amount,2);
  v_tax:=round(v_base*v_tax_rate,2);
  v_total:=v_base+v_tax;
  select coalesce(max(line_no),0)+1 into v_line_no from public.billing_invoice_line where invoice_id=p_invoice_id;

  insert into public.billing_invoice_line(
    invoice_id,line_no,line_type,service_date,code_system,code,description_snapshot,modifier_codes,diagnosis_codes,
    quantity,unit_amount,tax_rate,tax_amount,line_amount,patient_portion,scheme_portion,claim_eligible,metadata
  ) values(
    p_invoice_id,v_line_no,p_line_type,coalesce(p_service_date,v_invoice.invoice_date),
    case when p_line_type='transactional' then coalesce(p_code_system,'PRACTICE_CUSTOM') else coalesce(p_code_system,'PRACTICE_CUSTOM') end,
    case when p_line_type='transactional' then coalesce(p_code,'CUSTOM') else coalesce(p_code,'CLINICAL') end,
    trim(p_description),coalesce(p_modifier_codes,'{}'),v_diagnoses,
    p_quantity,p_unit_amount,v_tax_rate,v_tax,v_total,0,0,p_claim_eligible,
    jsonb_build_object(
      'claim_eligible',p_claim_eligible,
      'source','PracticeCtrl revenue engine',
      'diagnosis_source',case when p_line_type='clinical' and coalesce(cardinality(p_diagnosis_codes),0)=0 and coalesce(cardinality(v_diagnoses),0)>0 then 'Code10 encounter decisions' else 'user supplied' end
    )
  ) returning id into v_id;

  update public.billing_invoice
  set subtotal_amount=subtotal_amount+v_base,tax_amount=tax_amount+v_tax,total_amount=total_amount+v_total,
      balance_amount=greatest((total_amount+v_total)-credited_amount-received_amount,0),updated_at=now()
  where id=p_invoice_id;

  select count(*) into v_liability_count from public.billing_invoice_liability where invoice_id=p_invoice_id;
  if v_liability_count=1 then
    update public.billing_invoice_liability
    set amount=(select total_amount from public.billing_invoice where id=p_invoice_id)
    where invoice_id=p_invoice_id;
  end if;

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'line_added',v_user,jsonb_build_object('line_id',v_id,'line_no',v_line_no,'amount',v_total,'claim_eligible',p_claim_eligible,'diagnosis_codes',v_diagnoses));
  return v_id;
end;
$$;

create or replace function public.get_receivables_ageing(p_practice_id uuid,p_as_of date default current_date)
returns table(
  account_id uuid,
  account_number text,
  display_name text,
  account_type text,
  gross_invoice_outstanding numeric,
  unapplied_credit numeric,
  net_account_balance numeric,
  current_amount numeric,
  days_1_30 numeric,
  days_31_60 numeric,
  days_61_90 numeric,
  days_91_120 numeric,
  days_120_plus numeric
)
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
begin
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=p_practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin','auditor')
  ) then raise exception 'Revenue access required'; end if;

  return query
  with credits as (
    select c.invoice_id,c.account_id,coalesce(sum(c.total_amount),0)::numeric as amount
    from public.billing_credit_note c
    where c.practice_id=p_practice_id and c.status='final' and c.credit_note_date<=coalesce(p_as_of,current_date)
    group by c.invoice_id,c.account_id
  ),
  allocations as (
    select a.invoice_id,r.account_id,coalesce(sum(a.amount),0)::numeric as amount
    from public.billing_payment_allocation a
    join public.billing_payment_receipt r on r.id=a.receipt_id
    where r.practice_id=p_practice_id
      and r.receipt_date<=coalesce(p_as_of,current_date)
      and a.allocation_status='posted'
      and r.account_id is not null
    group by a.invoice_id,r.account_id
  ),
  inv as (
    select l.account_id,i.id invoice_id,coalesce(i.due_date,i.invoice_date) due_date,
           greatest(l.amount-coalesce(c.amount,0)-coalesce(a.amount,0),0)::numeric remaining
    from public.billing_invoice_liability l
    join public.billing_invoice i on i.id=l.invoice_id
    left join credits c on c.invoice_id=i.id and c.account_id=l.account_id
    left join allocations a on a.invoice_id=i.id and a.account_id=l.account_id
    where l.practice_id=p_practice_id
      and i.status not in ('draft','void')
      and i.invoice_date<=coalesce(p_as_of,current_date)
  ),
  receipt_totals as (
    select r.account_id,
      greatest(
        coalesce(sum(r.amount),0)
        - coalesce((
            select sum(a.amount)
            from public.billing_payment_allocation a
            join public.billing_payment_receipt rr on rr.id=a.receipt_id
            where rr.practice_id=p_practice_id
              and rr.account_id=r.account_id
              and rr.receipt_date<=coalesce(p_as_of,current_date)
              and a.allocation_status='posted'
          ),0),
        0
      )::numeric as unapplied
    from public.billing_payment_receipt r
    where r.practice_id=p_practice_id
      and r.account_id is not null
      and r.receipt_date<=coalesce(p_as_of,current_date)
      and r.amount>0
    group by r.account_id
  ),
  sums as (
    select a.id account_id,a.account_number,a.display_name,a.account_type,
      coalesce(sum(inv.remaining),0)::numeric gross,
      coalesce(max(rt.unapplied),0)::numeric unapplied,
      coalesce(sum(inv.remaining) filter(where inv.due_date>=coalesce(p_as_of,current_date)),0)::numeric current_amt,
      coalesce(sum(inv.remaining) filter(where coalesce(p_as_of,current_date)-inv.due_date between 1 and 30),0)::numeric d1,
      coalesce(sum(inv.remaining) filter(where coalesce(p_as_of,current_date)-inv.due_date between 31 and 60),0)::numeric d31,
      coalesce(sum(inv.remaining) filter(where coalesce(p_as_of,current_date)-inv.due_date between 61 and 90),0)::numeric d61,
      coalesce(sum(inv.remaining) filter(where coalesce(p_as_of,current_date)-inv.due_date between 91 and 120),0)::numeric d91,
      coalesce(sum(inv.remaining) filter(where coalesce(p_as_of,current_date)-inv.due_date>120),0)::numeric d120
    from public.billing_account a
    left join inv on inv.account_id=a.id
    left join receipt_totals rt on rt.account_id=a.id
    where a.practice_id=p_practice_id and a.status<>'closed'
    group by a.id,a.account_number,a.display_name,a.account_type
  )
  select s.account_id,s.account_number,s.display_name,s.account_type,s.gross,s.unapplied,
         (s.gross-s.unapplied)::numeric,s.current_amt,s.d1,s.d31,s.d61,s.d91,s.d120
  from sums s
  where s.gross<>0 or s.unapplied<>0
  order by (s.gross-s.unapplied) desc,s.display_name;
end;
$$;

revoke all on function public.set_billing_invoice_authorisation(uuid,uuid) from public,anon;
revoke all on function public.get_receivables_ageing(uuid,date) from public,anon;
grant execute on function public.set_billing_invoice_authorisation(uuid,uuid) to authenticated;
grant execute on function public.get_receivables_ageing(uuid,date) to authenticated;

