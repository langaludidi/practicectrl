begin;

create or replace function public.evaluate_payer_contract_requirements(
  p_practice_id uuid,
  p_patient_id uuid,
  p_encounter_id uuid,
  p_contract_id uuid,
  p_code_system text,
  p_code text,
  p_service_date date,
  p_modifier_codes text[],
  p_estimated_patient_liability numeric
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  c public.payer_contract%rowtype;
  r public.payer_billing_rule%rowtype;
  v_blockers jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_rules jsonb := '[]'::jsonb;
  v_authorisation_ok boolean;
  v_referral_ok boolean;
  v_required_modifier text;
  v_submission_days integer;
  v_balance_allowed boolean;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if p_practice_id is null or p_contract_id is null or p_service_date is null then
    raise exception 'Practice, contract and service date are required';
  end if;

  if not exists(
    select 1
    from public.practice_staff_member m
    where m.user_id=v_user
      and m.practice_id=p_practice_id
      and m.active
      and m.role in ('billing','practice_manager','clinical_admin','system_admin','auditor','practitioner')
  ) then
    raise exception 'Practice access required';
  end if;

  select * into c
  from public.payer_contract
  where id=p_contract_id
    and practice_id=p_practice_id;

  if not found then
    raise exception 'Payer contract not found in selected practice';
  end if;

  if c.status<>'active' then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code','CONTRACT_NOT_ACTIVE',
      'message','The payer agreement is not active for operational claim use',
      'contract_id',c.id,
      'contract_status',c.status
    ));
  end if;

  if p_service_date<c.effective_from
     or (c.effective_to is not null and p_service_date>c.effective_to) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'code','CONTRACT_OUTSIDE_EFFECTIVE_DATE',
      'message','The payer agreement is not effective on the service date',
      'contract_id',c.id,
      'effective_from',c.effective_from,
      'effective_to',c.effective_to
    ));
  end if;

  for r in
    select *
    from public.payer_billing_rule x
    where x.contract_id=c.id
      and x.status='active'
      and x.rule_type<>'tariff'
      and p_service_date>=x.effective_from
      and (x.effective_to is null or p_service_date<=x.effective_to)
      and (x.code_system is null or lower(x.code_system)=lower(p_code_system))
      and (x.code is null or x.code=p_code)
    order by x.rule_type,x.version desc,x.effective_from desc
  loop
    v_rules := v_rules || jsonb_build_array(jsonb_build_object(
      'rule_id',r.id,
      'rule_type',r.rule_type,
      'requirements',r.requirements,
      'rule_value',r.rule_value,
      'conditions',r.conditions,
      'version',r.version,
      'effective_from',r.effective_from,
      'effective_to',r.effective_to,
      'source_document_id',r.source_document_id
    ));

    if r.rule_type='authorisation'
       or coalesce((r.requirements->>'authorisation_required')::boolean,false) then
      select exists(
        select 1
        from public.scheme_authorisation a
        where a.practice_id=p_practice_id
          and a.patient_id=p_patient_id
          and a.status in ('approved','partially_approved')
          and (c.medical_scheme_id is null or a.medical_scheme_id is null or a.medical_scheme_id=c.medical_scheme_id)
          and (a.effective_from is null or a.effective_from<=p_service_date)
          and (a.effective_to is null or a.effective_to>=p_service_date)
          and (a.encounter_id is null or p_encounter_id is null or a.encounter_id=p_encounter_id)
          and (
            not exists(
              select 1 from public.scheme_authorisation_item ai
              where ai.authorisation_id=a.id
            )
            or exists(
              select 1
              from public.scheme_authorisation_item ai
              where ai.authorisation_id=a.id
                and ai.status in ('approved','partially_approved')
                and lower(ai.code_system)=lower(p_code_system)
                and ai.code=p_code
            )
          )
      ) into v_authorisation_ok;

      if not coalesce(v_authorisation_ok,false) then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'code','AUTHORISATION_REQUIRED',
          'message','The effective payer rule requires a valid authorisation for this service',
          'rule_id',r.id,
          'contract_id',c.id
        ));
      end if;
    end if;

    if r.rule_type='referral'
       or coalesce((r.requirements->>'referral_required')::boolean,false) then
      select exists(
        select 1
        from public.crm_patient_referral pr
        where pr.practice_id=p_practice_id
          and pr.patient_id=p_patient_id
          and (pr.referral_date is null or pr.referral_date<=p_service_date)
      ) into v_referral_ok;

      if not coalesce(v_referral_ok,false) then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'code','REFERRAL_REQUIRED',
          'message','The effective payer rule requires a referral to be recorded',
          'rule_id',r.id,
          'contract_id',c.id
        ));
      end if;
    end if;

    if r.rule_type='modifier' then
      v_required_modifier := coalesce(
        nullif(r.modifier_code,''),
        nullif(r.requirements->>'modifier_code',''),
        nullif(r.rule_value->>'modifier_code','')
      );

      if v_required_modifier is not null
         and not (v_required_modifier = any(coalesce(p_modifier_codes,'{}'::text[]))) then
        v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
          'code','CONTRACT_MODIFIER_MISSING',
          'message','The effective payer rule references a modifier that is not present on the claim line',
          'modifier_code',v_required_modifier,
          'rule_id',r.id
        ));
      end if;
    end if;

    if r.rule_type='exclusion' then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'code','PAYER_EXCLUSION',
        'message','An active payer rule marks this service as excluded and requires review before submission',
        'rule_id',r.id,
        'contract_id',c.id
      ));
    end if;

    if r.rule_type='submission_window' then
      v_submission_days := coalesce(
        nullif(r.requirements->>'submission_window_days','')::integer,
        nullif(r.requirements->>'days','')::integer,
        nullif(r.rule_value->>'submission_window_days','')::integer,
        nullif(r.rule_value->>'days','')::integer
      );
      if v_submission_days is not null
         and current_date > (p_service_date + v_submission_days) then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'code','SUBMISSION_WINDOW_EXCEEDED',
          'message','The service date is outside the configured payer submission window',
          'rule_id',r.id,
          'submission_window_days',v_submission_days
        ));
      end if;
    end if;

    if r.rule_type='balance_billing'
       and coalesce(p_estimated_patient_liability,0)>0 then
      v_balance_allowed := coalesce(
        (r.requirements->>'balance_billing_allowed')::boolean,
        (r.rule_value->>'balance_billing_allowed')::boolean,
        not coalesce((r.requirements->>'balance_billing_prohibited')::boolean,false),
        true
      );
      if not v_balance_allowed then
        v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
          'code','BALANCE_BILLING_REVIEW_REQUIRED',
          'message','The effective payer rule does not permit the estimated patient balance to be treated as ordinary patient liability',
          'rule_id',r.id,
          'estimated_patient_liability',p_estimated_patient_liability
        ));
      end if;
    end if;

    if r.rule_type in ('frequency_limit','bundle','pmb_chronic','copayment','other') then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object(
        'code','PAYER_RULE_REVIEW',
        'message','An additional effective payer rule applies and should be reviewed before submission',
        'rule_id',r.id,
        'rule_type',r.rule_type
      ));
    end if;
  end loop;

  return jsonb_build_object(
    'contract_id',c.id,
    'service_date',p_service_date,
    'code_system',p_code_system,
    'code',p_code,
    'blockers',v_blockers,
    'warnings',v_warnings,
    'applicable_rules',v_rules,
    'assessed_at',now()
  );
end
$function$;

revoke all on function public.evaluate_payer_contract_requirements(uuid,uuid,uuid,uuid,text,text,date,text[],numeric)
from public,anon;
grant execute on function public.evaluate_payer_contract_requirements(uuid,uuid,uuid,uuid,text,text,date,text[],numeric)
to authenticated,service_role;

commit;
