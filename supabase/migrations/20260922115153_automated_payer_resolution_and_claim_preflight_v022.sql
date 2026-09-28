
create or replace function public.auto_resolve_invoice_payer_lines(p_invoice_id uuid)
returns jsonb
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  i public.billing_invoice%rowtype;
  l public.billing_invoice_line%rowtype;
  v_practitioner uuid;
  v_reference numeric;
  v_tariff_rate uuid;
  j jsonb;
  v_resolved integer:=0;
  v_skipped integer:=0;
  v_blocked integer:=0;
  v_results jsonb:='[]'::jsonb;
  v_resolution uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into i from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if i.status<>'draft' then raise exception 'Automatic payer resolution is only available while the invoice is draft'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=i.practice_id and m.active and m.role in('billing','practice_manager','clinical_admin','system_admin')) then
    raise exception 'Billing role required';
  end if;

  v_practitioner:=null;
  if i.encounter_id is not null then
    select pp.id into v_practitioner
    from public.practice_encounter e
    join public.practitioner_profile pp on pp.practice_id=e.practice_id and pp.user_id=e.practitioner_user_id and pp.active
    where e.id=i.encounter_id and e.practice_id=i.practice_id
    limit 1;
  end if;

  for l in
    select * from public.billing_invoice_line
    where invoice_id=i.id and claim_eligible
    order by line_no
  loop
    if i.medical_scheme_id is null then
      v_skipped:=v_skipped+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('line_id',l.id,'line_no',l.line_no,'status','skipped','reason','No medical scheme is linked to the invoice'));
      continue;
    end if;

    v_reference:=l.reference_amount;
    v_tariff_rate:=l.tariff_rate_id;

    if v_reference is null then
      select tr.id,tr.amount into v_tariff_rate,v_reference
      from public.tariff_rate tr
      join public.tariff_schedule ts on ts.id=tr.tariff_schedule_id
      where ts.status='active'
        and tr.code_system=l.code_system and tr.code=l.code
        and (ts.practice_id is null or ts.practice_id=i.practice_id)
        and (ts.medical_scheme_id is null or ts.medical_scheme_id=i.medical_scheme_id)
        and (ts.medical_scheme_option_id is null or ts.medical_scheme_option_id=i.medical_scheme_option_id)
        and coalesce(l.service_date,i.invoice_date)>=ts.effective_from
        and (ts.effective_to is null or coalesce(l.service_date,i.invoice_date)<=ts.effective_to)
      order by
        case when ts.practice_id=i.practice_id then 0 else 1 end,
        case when ts.medical_scheme_option_id=i.medical_scheme_option_id then 0 else 1 end,
        case when ts.medical_scheme_id=i.medical_scheme_id then 0 else 1 end,
        ts.effective_from desc
      limit 1;
    end if;

    j:=public.preview_invoice_line_payer_resolution(l.id,v_practitioner,v_reference);

    if coalesce((j->>'contract_applicable')::boolean,false)=false then
      v_skipped:=v_skipped+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'line_id',l.id,'line_no',l.line_no,'status','not_applicable',
        'reference_amount',v_reference,'message','No active payer agreement applies to this line'
      ));
      continue;
    end if;

    if coalesce((j->>'matched')::boolean,false)=false then
      v_blocked:=v_blocked+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'line_id',l.id,'line_no',l.line_no,'status','blocked','code','CONTRACT_RULE_UNMATCHED',
        'reference_amount',v_reference,'contract_id',j->'applied_contract_id',
        'message','An active payer agreement applies but no effective tariff rule matched this line'
      ));
      continue;
    end if;

    if nullif(j->>'expected_contractual_amount','') is null then
      v_blocked:=v_blocked+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'line_id',l.id,'line_no',l.line_no,'status','blocked','code','REFERENCE_TARIFF_REQUIRED',
        'reference_amount',v_reference,'contract_id',j->'applied_contract_id','rule_id',j->'applied_rule_id',
        'message','The matched contract rule cannot calculate an expected amount because its reference tariff is unavailable'
      ));
      continue;
    end if;

    if l.payer_rule_resolution_id is not null
       and l.expected_contractual_amount is not distinct from nullif(j->>'expected_contractual_amount','')::numeric
       and l.expected_scheme_amount is not distinct from nullif(j->>'expected_scheme_amount','')::numeric
       and l.expected_patient_liability is not distinct from nullif(j->>'estimated_patient_liability','')::numeric
       and l.reference_amount is not distinct from v_reference then
      v_skipped:=v_skipped+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'line_id',l.id,'line_no',l.line_no,'status','current',
        'resolution_id',l.payer_rule_resolution_id,'expected_scheme_amount',l.expected_scheme_amount,
        'estimated_patient_liability',l.expected_patient_liability
      ));
      continue;
    end if;

    v_resolution:=public.record_invoice_line_payer_resolution(l.id,v_practitioner,v_reference);
    update public.billing_invoice_line set tariff_rate_id=coalesce(tariff_rate_id,v_tariff_rate) where id=l.id;
    v_resolved:=v_resolved+1;
    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'line_id',l.id,'line_no',l.line_no,'status','resolved','resolution_id',v_resolution,
      'reference_amount',v_reference,'expected_scheme_amount',j->'expected_scheme_amount',
      'estimated_patient_liability',j->'estimated_patient_liability','confidence',j->'confidence'
    ));
  end loop;

  return jsonb_build_object(
    'invoice_id',i.id,'resolved',v_resolved,'skipped',v_skipped,'blocked',v_blocked,
    'practitioner_id',v_practitioner,'lines',v_results
  );
end
$function$;

revoke all on function public.auto_resolve_invoice_payer_lines(uuid) from public,anon;
grant execute on function public.auto_resolve_invoice_payer_lines(uuid) to authenticated,service_role;

create or replace function public.run_invoice_claim_preflight(p_invoice_id uuid,p_persist boolean default true)
returns jsonb
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  i public.billing_invoice%rowtype;
  l public.billing_invoice_line%rowtype;
  rr public.payer_rule_resolution%rowtype;
  v_auto jsonb:='{}'::jsonb;
  v_req jsonb;
  v_findings jsonb:='[]'::jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_blocks integer:=0;
  v_warns integer:=0;
  v_membership boolean:=false;
  x jsonb;
  v_status text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=(select practice_id from public.billing_invoice where id=p_invoice_id) and m.active and m.role in('billing','practice_manager','clinical_admin','system_admin','auditor')) then
    raise exception 'Authorised finance or clinical administration role required';
  end if;
  select * into i from public.billing_invoice where id=p_invoice_id;
  if not found then raise exception 'Invoice not found or not accessible'; end if;

  if i.status='draft' then
    if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required for draft pre-flight'; end if;
    v_auto:=public.auto_resolve_invoice_payer_lines(i.id);
  end if;

  if i.patient_id is null then
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','PATIENT_REQUIRED','message','A patient link is required before a medical-scheme claim can be prepared'));
    v_blocks:=v_blocks+1;
  end if;
  if i.medical_scheme_id is null and exists(select 1 from public.billing_invoice_line where invoice_id=i.id and claim_eligible) then
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','SCHEME_REQUIRED','message','Claim-eligible lines require a medical scheme'));
    v_blocks:=v_blocks+1;
  end if;

  if i.patient_id is not null and i.medical_scheme_id is not null then
    select exists(
      select 1 from public.crm_patient_scheme_membership m
      where m.practice_id=i.practice_id and m.patient_id=i.patient_id
        and m.medical_scheme_id=i.medical_scheme_id
        and (i.medical_scheme_option_id is null or m.medical_scheme_option_id=i.medical_scheme_option_id)
        and m.membership_status='active_verified'
        and (m.effective_from is null or m.effective_from<=i.invoice_date)
        and (m.effective_to is null or m.effective_to>=i.invoice_date)
    ) into v_membership;
    if not v_membership then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','MEMBERSHIP_UNVERIFIED','message','No active verified scheme membership matches this patient, scheme, option and invoice date'));
      v_blocks:=v_blocks+1;
    end if;
  end if;

  for l in select * from public.billing_invoice_line where invoice_id=i.id and claim_eligible order by line_no loop
    if l.service_date is null or nullif(trim(coalesce(l.code,'')),'') is null or cardinality(l.diagnosis_codes)=0 then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','LINE_INCOMPLETE','invoice_line_id',l.id,'line_no',l.line_no,'message','Claim line requires service date, procedure code and diagnosis coding'));
      v_blocks:=v_blocks+1;
    end if;

    if l.payer_rule_resolution_id is not null then
      select * into rr from public.payer_rule_resolution where id=l.payer_rule_resolution_id;
    else
      rr:=null;
    end if;

    if rr.applied_contract_id is not null then
      v_req:=public.evaluate_payer_contract_requirements(
        i.practice_id,i.patient_id,i.encounter_id,rr.applied_contract_id,l.code_system,l.code,
        coalesce(l.service_date,i.invoice_date),l.modifier_codes,l.expected_patient_liability
      );
      for x in select value from jsonb_array_elements(coalesce(v_req->'blockers','[]'::jsonb)) loop
        v_findings:=v_findings||jsonb_build_array(
          x||jsonb_build_object('severity','blocking','invoice_line_id',l.id,'line_no',l.line_no)
        );
        v_blocks:=v_blocks+1;
      end loop;
      for x in select value from jsonb_array_elements(coalesce(v_req->'warnings','[]'::jsonb)) loop
        v_findings:=v_findings||jsonb_build_array(
          x||jsonb_build_object('severity','warning','invoice_line_id',l.id,'line_no',l.line_no)
        );
        v_warns:=v_warns+1;
      end loop;

      if l.expected_scheme_amount is null then
        v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','CONTRACT_AMOUNT_UNRESOLVED','invoice_line_id',l.id,'line_no',l.line_no,'message','The active payer contract did not produce an expected scheme amount'));
        v_blocks:=v_blocks+1;
      elsif l.scheme_portion>0 and abs(l.scheme_portion-l.expected_scheme_amount)>0.01 then
        v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','TARIFF_LIABILITY_MISMATCH','invoice_line_id',l.id,'line_no',l.line_no,'message','Scheme liability differs from the effective contractual amount','scheme_portion',l.scheme_portion,'expected_scheme_amount',l.expected_scheme_amount));
        v_blocks:=v_blocks+1;
      end if;
    elsif i.medical_scheme_id is not null and exists(
      select 1 from public.payer_contract pc
      where pc.practice_id=i.practice_id and pc.status='active'
        and pc.medical_scheme_id=i.medical_scheme_id
        and (pc.medical_scheme_option_id is null or pc.medical_scheme_option_id=i.medical_scheme_option_id)
        and coalesce(l.service_date,i.invoice_date)>=pc.effective_from
        and (pc.effective_to is null or coalesce(l.service_date,i.invoice_date)<=pc.effective_to)
    ) then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','CONTRACT_RATE_UNRESOLVED','invoice_line_id',l.id,'line_no',l.line_no,'message','An active payer agreement applies but this line has no recorded contract resolution'));
      v_blocks:=v_blocks+1;
    end if;

    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'invoice_line_id',l.id,'line_no',l.line_no,'code_system',l.code_system,'code',l.code,
      'charged_amount',l.line_amount,'reference_amount',l.reference_amount,
      'expected_contractual_amount',l.expected_contractual_amount,'expected_scheme_amount',l.expected_scheme_amount,
      'estimated_patient_liability',l.expected_patient_liability,'payer_rule_resolution_id',l.payer_rule_resolution_id,
      'contract_id',rr.applied_contract_id,'rule_id',rr.applied_rule_id,
      'requirements',coalesce(v_req,'{}'::jsonb)
    ));
    v_req:=null; rr:=null;
  end loop;

  if not exists(select 1 from public.billing_invoice_line where invoice_id=i.id and claim_eligible) then
    v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','NO_CLAIM_LINES','message','Invoice has no claim-eligible clinical lines'));
    v_blocks:=v_blocks+1;
  end if;

  v_status:=case when v_blocks>0 then 'blocked' when v_warns>0 then 'review' else 'ready' end;

  if p_persist then
    if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required to persist pre-flight results'; end if;
    update public.billing_validation_event
       set status='resolved',resolved_at=now(),resolution_note='Superseded by a newer automated claim pre-flight'
     where invoice_id=i.id and source='payer_claim_preflight' and status in('open','acknowledged');

    for x in select value from jsonb_array_elements(v_findings) loop
      insert into public.billing_validation_event(invoice_id,invoice_line_id,rule_code,severity,message,source,status,actor_user_id)
      values(
        i.id,nullif(x->>'invoice_line_id','')::uuid,coalesce(x->>'code','PREFLIGHT'),
        case when x->>'severity'='warning' then 'warning' else 'blocking' end,
        coalesce(x->>'message','Claim pre-flight finding'),'payer_claim_preflight','open',v_user
      );
    end loop;

    insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
    values(i.id,'validated',v_user,jsonb_build_object(
      'validation','payer_claim_preflight','status',v_status,'blocking_count',v_blocks,'warning_count',v_warns,
      'auto_resolution',v_auto,'verified_membership_active',v_membership
    ));
  end if;

  return jsonb_build_object(
    'invoice_id',i.id,'invoice_number',i.invoice_number,'status',v_status,
    'blocking_count',v_blocks,'warning_count',v_warns,'verified_membership_active',v_membership,
    'auto_resolution',v_auto,'findings',v_findings,'lines',v_lines,'assessed_at',now()
  );
end
$function$;

revoke all on function public.run_invoice_claim_preflight(uuid,boolean) from public,anon;
grant execute on function public.run_invoice_claim_preflight(uuid,boolean) to authenticated,service_role;

