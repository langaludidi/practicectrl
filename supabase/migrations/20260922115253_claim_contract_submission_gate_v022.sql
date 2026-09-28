
create or replace function public.assess_claim_contract_requirements(p_claim_id uuid)
returns jsonb
language plpgsql
stable
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  c public.claim_record%rowtype;
  l public.claim_line%rowtype;
  rr public.payer_rule_resolution%rowtype;
  il public.billing_invoice_line%rowtype;
  v_req jsonb;
  v_findings jsonb:='[]'::jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_blocks integer:=0;
  v_warns integer:=0;
  x jsonb;
begin
  if v_user is null then
    return jsonb_build_object('status','blocked','blocking_count',1,'warning_count',0,'findings',jsonb_build_array(jsonb_build_object('severity','blocking','code','AUTH_REQUIRED','message','Authentication required')));
  end if;
  select * into c from public.claim_record where id=p_claim_id;
  if not found then
    return jsonb_build_object('status','blocked','blocking_count',1,'warning_count',0,'findings',jsonb_build_array(jsonb_build_object('severity','blocking','code','CLAIM_NOT_FOUND','message','Claim not found or inaccessible')));
  end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=c.practice_id and m.active and m.role in('billing','practice_manager','clinical_admin','system_admin','auditor')) then
    return jsonb_build_object('status','blocked','blocking_count',1,'warning_count',0,'findings',jsonb_build_array(jsonb_build_object('severity','blocking','code','ROLE_REQUIRED','message','Authorised practice role required')));
  end if;

  for l in select * from public.claim_line where claim_id=c.id order by line_no loop
    rr:=null; il:=null; v_req:=null;
    if l.invoice_line_id is not null then select * into il from public.billing_invoice_line where id=l.invoice_line_id; end if;
    if l.payer_rule_resolution_id is not null then select * into rr from public.payer_rule_resolution where id=l.payer_rule_resolution_id; end if;

    if rr.applied_contract_id is not null then
      v_req:=public.evaluate_payer_contract_requirements(
        c.practice_id,c.patient_id,c.encounter_id,rr.applied_contract_id,l.code_system,l.code,
        coalesce(il.service_date,c.service_from,current_date),l.modifier_codes,
        coalesce(il.expected_patient_liability,l.patient_liability)
      );
      for x in select value from jsonb_array_elements(coalesce(v_req->'blockers','[]'::jsonb)) loop
        v_findings:=v_findings||jsonb_build_array(x||jsonb_build_object('severity','blocking','claim_line_id',l.id,'line_no',l.line_no));
        v_blocks:=v_blocks+1;
      end loop;
      for x in select value from jsonb_array_elements(coalesce(v_req->'warnings','[]'::jsonb)) loop
        v_findings:=v_findings||jsonb_build_array(x||jsonb_build_object('severity','warning','claim_line_id',l.id,'line_no',l.line_no));
        v_warns:=v_warns+1;
      end loop;
      if l.expected_scheme_amount is null then
        v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','EXPECTED_SCHEME_AMOUNT_MISSING','claim_line_id',l.id,'line_no',l.line_no,'message','Contract-backed claim line has no expected scheme amount'));
        v_blocks:=v_blocks+1;
      end if;
    elsif c.medical_scheme_id is not null and exists(
      select 1 from public.payer_contract pc
      where pc.practice_id=c.practice_id and pc.status='active' and pc.medical_scheme_id=c.medical_scheme_id
        and (pc.medical_scheme_option_id is null or pc.medical_scheme_option_id=c.medical_scheme_option_id)
        and coalesce(il.service_date,c.service_from,current_date)>=pc.effective_from
        and (pc.effective_to is null or coalesce(il.service_date,c.service_from,current_date)<=pc.effective_to)
    ) then
      v_findings:=v_findings||jsonb_build_array(jsonb_build_object('severity','blocking','code','CLAIM_CONTRACT_RESOLUTION_MISSING','claim_line_id',l.id,'line_no',l.line_no,'message','An active payer agreement applies but the claim line has no preserved payer-rule resolution'));
      v_blocks:=v_blocks+1;
    end if;

    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'claim_line_id',l.id,'line_no',l.line_no,'code_system',l.code_system,'code',l.code,
      'claimed_amount',l.claimed_amount,'expected_contractual_amount',l.expected_contractual_amount,
      'expected_scheme_amount',l.expected_scheme_amount,'payer_rule_resolution_id',l.payer_rule_resolution_id,
      'contract_id',rr.applied_contract_id,'rule_id',rr.applied_rule_id,'requirements',coalesce(v_req,'{}'::jsonb)
    ));
  end loop;

  return jsonb_build_object(
    'claim_id',c.id,
    'status',case when v_blocks>0 then 'blocked' when v_warns>0 then 'review' else 'ready' end,
    'blocking_count',v_blocks,'warning_count',v_warns,'findings',v_findings,'lines',v_lines,'assessed_at',now()
  );
end
$function$;

revoke all on function public.assess_claim_contract_requirements(uuid) from public,anon;
grant execute on function public.assess_claim_contract_requirements(uuid) to authenticated,service_role;

create or replace function public.authorise_claim_submission(p_claim_id uuid)
returns jsonb
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid:=(select auth.uid());
  c public.claim_record%rowtype;
  r jsonb;
  pc jsonb;
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
  select * into c from public.claim_record where id=p_claim_id for update;
  if not found then raise exception 'Claim not found or inaccessible';end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=c.practice_id and m.active and m.role in('billing','practice_manager','system_admin')) then raise exception 'Billing role required';end if;
  if c.claim_status not in('draft','validated','ready') then raise exception 'Claim is not in a pre-submission state';end if;

  pc:=public.assess_claim_contract_requirements(c.id);
  if coalesce(pc->>'status','blocked')='blocked' then
    raise exception 'Payer contract gate blocked claim submission: %',
      jsonb_build_object('blocking_count',pc->'blocking_count','warning_count',pc->'warning_count','findings',pc->'findings')::text;
  end if;

  r:=public.assess_revenue_integrity(c.invoice_id,c.id,true);
  if coalesce(r->>'status','blocked')<>'ready' then
    raise exception 'Revenue integrity gate blocked claim submission: %',
      jsonb_build_object('score',r->'score','blocking_count',r->'blocking_count','warning_count',r->'warning_count','findings',r->'findings')::text;
  end if;
  update public.claim_record set claim_status='ready',updated_at=now() where id=p_claim_id;
  return r||jsonb_build_object('claim_id',p_claim_id,'authorised',true,'payer_contract_preflight',pc);
end
$function$;

revoke all on function public.authorise_claim_submission(uuid) from public,anon;
grant execute on function public.authorise_claim_submission(uuid) to authenticated,service_role;

create or replace function public.prepare_claim_from_invoice(p_invoice_id uuid)
returns uuid
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid:=(select auth.uid());
  v_invoice public.billing_invoice%rowtype;
  v_integrity jsonb;
  v_claim_id uuid;
begin
  if v_user is null then raise exception 'Authentication required';end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required';end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible';end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in('billing','practice_manager','system_admin')) then raise exception 'Billing role required';end if;
  v_integrity:=public.assess_revenue_integrity(p_invoice_id,null,true);
  if coalesce(v_integrity->>'status','blocked')<>'ready' then
    raise exception 'Revenue integrity gate blocked claim preparation: %',
      jsonb_build_object('score',v_integrity->'score','blocking_count',v_integrity->'blocking_count','warning_count',v_integrity->'warning_count','findings',v_integrity->'findings')::text;
  end if;
  if exists(select 1 from public.claim_record c where c.invoice_id=p_invoice_id and c.claim_status not in('cancelled','reversed')) then raise exception 'An active claim already exists for this invoice';end if;

  insert into public.claim_record(
    practice_id,invoice_id,patient_id,encounter_id,medical_scheme_id,medical_scheme_option_id,scheme_authorisation_id,
    claim_status,service_from,service_to,total_claimed,created_by
  )
  values(
    v_invoice.practice_id,v_invoice.id,v_invoice.patient_id,v_invoice.encounter_id,v_invoice.medical_scheme_id,
    v_invoice.medical_scheme_option_id,v_invoice.scheme_authorisation_id,'draft',
    coalesce((select min(service_date) from public.billing_invoice_line where invoice_id=v_invoice.id and claim_eligible),v_invoice.invoice_date),
    coalesce((select max(service_date) from public.billing_invoice_line where invoice_id=v_invoice.id and claim_eligible),v_invoice.invoice_date),
    v_invoice.scheme_portion,v_user
  ) returning id into v_claim_id;

  insert into public.claim_line(
    claim_id,invoice_line_id,line_no,code_system,code,modifier_codes,diagnosis_codes,quantity,claimed_amount,status,
    expected_contractual_amount,expected_scheme_amount,payer_rule_resolution_id
  )
  select v_claim_id,l.id,l.line_no,l.code_system,l.code,l.modifier_codes,l.diagnosis_codes,l.quantity,l.line_amount,'draft',
         l.expected_contractual_amount,l.expected_scheme_amount,l.payer_rule_resolution_id
  from public.billing_invoice_line l
  where l.invoice_id=p_invoice_id and l.claim_eligible=true
  order by l.line_no;

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'validated',v_user,jsonb_build_object(
    'claim_id',v_claim_id,'claim_prepared',true,'revenue_integrity_score',v_integrity->'score',
    'revenue_integrity_assessment_id',v_integrity->'assessment_id','expected_scheme_amount',v_integrity->'expected_scheme_amount',
    'encounter_id',v_invoice.encounter_id
  ));
  return v_claim_id;
end
$function$;

revoke all on function public.prepare_claim_from_invoice(uuid) from public,anon;
grant execute on function public.prepare_claim_from_invoice(uuid) to authenticated,service_role;

