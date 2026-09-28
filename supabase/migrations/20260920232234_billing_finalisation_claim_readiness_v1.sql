
begin;

create or replace function public.finalise_billing_invoice(p_invoice_id uuid)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_invoice public.billing_invoice%rowtype;
  v_line_total numeric(14,2);
  v_line_count integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then
    raise exception 'MFA assurance level 2 required';
  end if;

  select * into v_invoice
  from public.billing_invoice
  where id=p_invoice_id
  for update;

  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if v_invoice.status <> 'draft' then raise exception 'Only draft invoices can be finalised'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  select count(*),coalesce(sum(line_amount),0)
  into v_line_count,v_line_total
  from public.billing_invoice_line
  where invoice_id=p_invoice_id;

  if v_line_count < 1 then raise exception 'Invoice has no lines'; end if;
  if round(v_line_total,2) <> round(v_invoice.total_amount,2) then
    raise exception 'Invoice total does not match its line total';
  end if;
  if round(v_invoice.patient_portion + v_invoice.scheme_portion,2) <> round(v_invoice.total_amount,2) then
    raise exception 'Patient and scheme portions do not equal invoice total';
  end if;

  if exists (
    select 1 from public.billing_validation_event e
    where e.invoice_id=p_invoice_id
      and e.severity='blocking'
      and e.status in ('open','acknowledged')
  ) then raise exception 'Unresolved blocking billing validation exists'; end if;

  update public.billing_invoice
  set status=case when balance_amount=0 then 'paid' else 'final' end,
      finalised_by=v_user,
      finalised_at=now(),
      updated_at=now()
  where id=p_invoice_id;

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'finalised',v_user,jsonb_build_object(
    'line_count',v_line_count,
    'total_amount',v_invoice.total_amount,
    'patient_portion',v_invoice.patient_portion,
    'scheme_portion',v_invoice.scheme_portion
  ));

  return p_invoice_id;
end;
$$;

revoke all on function public.finalise_billing_invoice(uuid) from public,anon;
grant execute on function public.finalise_billing_invoice(uuid) to authenticated;

create or replace function public.assess_claim_readiness(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
declare
  v_invoice public.billing_invoice%rowtype;
  v_reasons jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_claimable_count integer := 0;
  v_active_mit boolean := false;
  v_production_route boolean := false;
  v_licensed_procedure_rows integer := 0;
begin
  select * into v_invoice
  from public.billing_invoice
  where id=p_invoice_id;

  if not found then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Invoice not found or not accessible'),'warnings','[]'::jsonb);
  end if;

  if v_invoice.status not in ('final','part_paid','outstanding') then
    v_reasons := v_reasons || jsonb_build_array('Invoice must be finalised before claim preparation');
  end if;

  if v_invoice.patient_id is null then
    v_reasons := v_reasons || jsonb_build_array('Invoice has no patient link');
  end if;

  if v_invoice.medical_scheme_id is null then
    v_reasons := v_reasons || jsonb_build_array('No medical scheme is linked to the invoice');
  end if;

  select count(*) into v_claimable_count
  from public.billing_invoice_line l
  where l.invoice_id=p_invoice_id
    and coalesce((l.metadata->>'claim_eligible')::boolean,true)=true;

  if v_claimable_count < 1 then
    v_reasons := v_reasons || jsonb_build_array('Invoice has no claim-eligible procedure lines');
  end if;

  if exists (
    select 1 from public.billing_invoice_line l
    where l.invoice_id=p_invoice_id
      and coalesce((l.metadata->>'claim_eligible')::boolean,true)=true
      and cardinality(l.diagnosis_codes)=0
  ) then
    v_reasons := v_reasons || jsonb_build_array('One or more claim-eligible lines have no diagnosis code');
  end if;

  if exists (
    select 1 from public.billing_invoice_line l
    where l.invoice_id=p_invoice_id
      and coalesce((l.metadata->>'claim_eligible')::boolean,true)=true
      and l.code_system <> 'SAMA_CCSA'
  ) then
    v_reasons := v_reasons || jsonb_build_array('Claim-eligible procedure lines are not using the licensed SAMA CCSA code system');
  end if;

  select count(*) into v_licensed_procedure_rows
  from public.billing_code_reference r
  join public.source_dataset_release sr on sr.id=r.source_release_id
  join public.source_dataset d on d.id=sr.dataset_id
  where r.code_system='SAMA_CCSA'
    and r.active
    and sr.status='active'
    and d.licence_required=true;

  if v_licensed_procedure_rows=0 then
    v_reasons := v_reasons || jsonb_build_array('No active licensed SAMA CCSA dataset is available');
  end if;

  select exists(
    select 1 from public.coding_source_release
    where authority='NDOH'
      and source_name='ICD-10 Master Industry Table'
      and status='active'
  ) into v_active_mit;

  if not v_active_mit then
    v_reasons := v_reasons || jsonb_build_array('No active authoritative NDoH MIT release is available');
  end if;

  if v_invoice.medical_scheme_id is not null then
    select exists(
      select 1
      from public.payer_transaction_route r
      join public.integration_adapter_capability a
        on a.provider_id=r.provider_id
       and a.interface_id=r.interface_id
       and a.capability_code=r.capability_code
      join public.practice_integration_connection c
        on c.practice_id=v_invoice.practice_id
       and c.provider_id=r.provider_id
       and c.interface_id=r.interface_id
       and c.environment='production'
       and c.status in ('production_ready','active')
      where r.medical_scheme_id=v_invoice.medical_scheme_id
        and (r.medical_scheme_option_id is null or r.medical_scheme_option_id=v_invoice.medical_scheme_option_id)
        and r.capability_code='claim_submit'
        and a.executable_production=true
        and (r.effective_from is null or r.effective_from<=v_invoice.invoice_date)
        and (r.effective_to is null or r.effective_to>=v_invoice.invoice_date)
    ) into v_production_route;
  end if;

  if not v_production_route then
    v_reasons := v_reasons || jsonb_build_array('No accredited executable production claim route exists for this scheme/option');
  end if;

  if v_invoice.scheme_portion <= 0 then
    v_warnings := v_warnings || jsonb_build_array('Invoice currently has no scheme portion');
  end if;

  return jsonb_build_object(
    'ready',jsonb_array_length(v_reasons)=0,
    'reasons',v_reasons,
    'warnings',v_warnings,
    'invoice_id',p_invoice_id,
    'claimable_lines',v_claimable_count,
    'authoritative_mit_active',v_active_mit,
    'licensed_procedure_data_active',v_licensed_procedure_rows>0,
    'production_route_active',v_production_route
  );
end;
$$;

revoke all on function public.assess_claim_readiness(uuid) from public,anon;
grant execute on function public.assess_claim_readiness(uuid) to authenticated;

commit;
