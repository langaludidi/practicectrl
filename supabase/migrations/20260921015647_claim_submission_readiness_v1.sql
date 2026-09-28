
create or replace function public.assess_claim_submission_readiness(p_claim_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
declare
  v_claim public.claim_record%rowtype;
  v_invoice public.billing_invoice%rowtype;
  v_reasons jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_mit boolean := false;
  v_ccsa boolean := false;
  v_membership boolean := false;
  v_route boolean := false;
  v_line_count integer := 0;
begin
  select * into v_claim from public.claim_record where id=p_claim_id;
  if not found then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Claim not found or not accessible'),'warnings','[]'::jsonb);
  end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=v_claim.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin','auditor')
  ) then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Finance-authorised PracticeCtrl role required'),'warnings','[]'::jsonb);
  end if;

  if v_claim.invoice_id is null then
    v_reasons:=v_reasons||jsonb_build_array('Claim is not linked to an invoice');
  else
    select * into v_invoice from public.billing_invoice where id=v_claim.invoice_id;
    if not found then
      v_reasons:=v_reasons||jsonb_build_array('Linked invoice is unavailable');
    elsif v_invoice.status not in ('final','part_paid','outstanding','paid') then
      v_reasons:=v_reasons||jsonb_build_array('Linked invoice is not finalised');
    end if;
  end if;

  if v_claim.patient_id is null then
    v_reasons:=v_reasons||jsonb_build_array('Claim has no patient link');
  end if;
  if v_claim.medical_scheme_id is null then
    v_reasons:=v_reasons||jsonb_build_array('Claim has no medical scheme link');
  end if;

  select count(*) into v_line_count from public.claim_line where claim_id=p_claim_id;
  if v_line_count<1 then
    v_reasons:=v_reasons||jsonb_build_array('Claim has no claim lines');
  end if;

  if exists (
    select 1 from public.claim_line l
    where l.claim_id=p_claim_id
      and (cardinality(l.diagnosis_codes)=0 or l.code_system<>'SAMA_CCSA')
  ) then
    v_reasons:=v_reasons||jsonb_build_array('One or more claim lines lack diagnosis coding or licensed SAMA CCSA procedure coding');
  end if;

  select exists(
    select 1 from public.coding_source_release
    where authority='NDOH'
      and source_name='ICD-10 Master Industry Table'
      and status='active'
  ) into v_mit;
  if not v_mit then
    v_reasons:=v_reasons||jsonb_build_array('No active authoritative NDoH MIT release is available');
  end if;

  select exists(
    select 1
    from public.billing_code_reference r
    join public.source_dataset_release sr on sr.id=r.source_release_id
    join public.source_dataset d on d.id=sr.dataset_id
    where r.code_system='SAMA_CCSA'
      and r.active
      and sr.status='active'
      and d.licence_required=true
  ) into v_ccsa;
  if not v_ccsa then
    v_reasons:=v_reasons||jsonb_build_array('No active licensed SAMA CCSA dataset is available');
  end if;

  if v_claim.patient_id is not null and v_claim.medical_scheme_id is not null then
    select exists(
      select 1
      from public.crm_patient_scheme_membership m
      where m.practice_id=v_claim.practice_id
        and m.patient_id=v_claim.patient_id
        and m.medical_scheme_id=v_claim.medical_scheme_id
        and (v_claim.medical_scheme_option_id is null or m.medical_scheme_option_id=v_claim.medical_scheme_option_id)
        and m.membership_status='active_verified'
        and (m.effective_from is null or m.effective_from<=coalesce(v_claim.service_from,current_date))
        and (m.effective_to is null or m.effective_to>=coalesce(v_claim.service_to,v_claim.service_from,current_date))
    ) into v_membership;
  end if;
  if not v_membership then
    v_reasons:=v_reasons||jsonb_build_array('No active verified scheme membership matches this patient/scheme/option/service date');
  end if;

  if v_claim.medical_scheme_id is not null then
    select exists(
      select 1
      from public.payer_transaction_route r
      join public.integration_adapter_capability a
        on a.provider_id=r.provider_id
       and a.interface_id=r.interface_id
       and a.capability_code='claim_submit'
      join public.practice_integration_connection c
        on c.practice_id=v_claim.practice_id
       and c.provider_id=r.provider_id
       and c.interface_id=r.interface_id
       and c.environment='production'
       and c.status in ('production_ready','active')
      where r.medical_scheme_id=v_claim.medical_scheme_id
        and (r.medical_scheme_option_id is null or r.medical_scheme_option_id=v_claim.medical_scheme_option_id)
        and r.capability_code='claim_submit'
        and r.support_status<>'not_supported'
        and a.executable_production=true
        and (r.effective_from is null or r.effective_from<=coalesce(v_claim.service_from,current_date))
        and (r.effective_to is null or r.effective_to>=coalesce(v_claim.service_to,v_claim.service_from,current_date))
    ) into v_route;
  end if;
  if not v_route then
    v_reasons:=v_reasons||jsonb_build_array('No accredited executable production claim route exists for this scheme/option');
  end if;

  if v_claim.claim_status<>'draft' then
    v_warnings:=v_warnings||jsonb_build_array('Claim is not in draft status; submission controls must respect the existing lifecycle state');
  end if;
  if v_claim.total_claimed<=0 then
    v_reasons:=v_reasons||jsonb_build_array('Claimed amount must be greater than zero');
  end if;

  return jsonb_build_object(
    'ready',jsonb_array_length(v_reasons)=0 and v_claim.claim_status='draft',
    'reasons',v_reasons,
    'warnings',v_warnings,
    'claim_id',p_claim_id,
    'claim_status',v_claim.claim_status,
    'claim_lines',v_line_count,
    'authoritative_mit_active',v_mit,
    'licensed_procedure_data_active',v_ccsa,
    'verified_membership_active',v_membership,
    'production_route_active',v_route
  );
end;
$$;

revoke all on function public.assess_claim_submission_readiness(uuid) from public,anon;
grant execute on function public.assess_claim_submission_readiness(uuid) to authenticated;

