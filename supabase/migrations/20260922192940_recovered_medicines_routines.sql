-- Recovered medicines routines, private storage and sandbox integration fixtures.
-- Schema and governed reference configuration only; no patient data or credentials are copied.
begin;
insert into public.integration_provider(slug,name,provider_type,lifecycle_status) values ('emguidance-script','EMGuidance Script','other','contact_required') on conflict(slug) do nothing;
insert into public.integration_interface(provider_id,name,interface_type,direction,sync_mode,status) select id,'EMGuidance Script integration','api','bidirectional','realtime','contact_required' from public.integration_provider where slug='emguidance-script' on conflict(provider_id,name) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('drug_interaction_check','Drug interaction checking','clinical','Evaluate a proposed medication list/prescription against governed drug-interaction content.',true,true) on conflict(code) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('pharmacy_directory','Pharmacy directory','clinical','Retrieve pharmacy destinations supported by a prescribing platform.',false,false) on conflict(code) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('prescription_status','Electronic prescription status','clinical','Receive prescription delivery/fulfilment status where supported.',true,true) on conflict(code) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('prescription_transmit','Electronic prescription transmission','clinical','Transmit a clinician-approved prescription through an approved electronic prescribing rail.',true,true) on conflict(code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'drug_interaction_check','not_started',false,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='emguidance-script' and i.name='EMGuidance Script integration' on conflict(provider_id,interface_id,capability_code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'pharmacy_directory','not_started',false,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='emguidance-script' and i.name='EMGuidance Script integration' on conflict(provider_id,interface_id,capability_code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'prescription_status','not_started',false,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='emguidance-script' and i.name='EMGuidance Script integration' on conflict(provider_id,interface_id,capability_code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'prescription_transmit','not_started',false,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='emguidance-script' and i.name='EMGuidance Script integration' on conflict(provider_id,interface_id,capability_code) do nothing;

CREATE OR REPLACE FUNCTION private.assess_prescription_safety_internal(p_prescription_id uuid, p_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  v_rx public.prescription%rowtype;
  v_assessment_id uuid;
  v_version integer;
  v_reference_ready boolean:=false;
  v_interaction_ready boolean:=false;
  v_blocking integer:=0;
  v_warning integer:=0;
  v_hash text;
  v_payload jsonb;
  r record;
begin
  if (select auth.uid()) is null or (select auth.uid())<>p_user then
    raise exception 'Authenticated user mismatch';
  end if;

  select * into v_rx from public.prescription where id=p_prescription_id for update;
  if not found then raise exception 'Prescription not found'; end if;
  if v_rx.prescriber_user_id<>p_user then raise exception 'Only the prescribing practitioner may assess this prescription'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=p_user and m.practice_id=v_rx.practice_id and m.active and m.role='practitioner'
  ) then raise exception 'Active practitioner role required'; end if;
  if v_rx.status not in ('draft','safety_review','blocked') then
    raise exception 'Prescription is not editable for safety assessment';
  end if;

  select exists(
    select 1
    from public.medicine_reference_product p
    join public.source_dataset_release rel on rel.id=p.source_release_id
    where p.status='active' and rel.status='active' and rel.activated_at is not null
      and (p.effective_from is null or p.effective_from<=current_date)
      and (p.effective_to is null or p.effective_to>=current_date)
  ) into v_reference_ready;

  select exists(
    select 1
    from public.medicine_interaction_rule ir
    join public.source_dataset_release rel on rel.id=ir.source_release_id
    where ir.active and rel.status='active' and rel.activated_at is not null
      and (ir.effective_from is null or ir.effective_from<=current_date)
      and (ir.effective_to is null or ir.effective_to>=current_date)
  ) into v_interaction_ready;

  select jsonb_build_object(
    'prescription_id',v_rx.id,
    'patient_id',v_rx.patient_id,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'product_id',i.product_id,'ingredient_id',i.ingredient_id,'medication_name',i.medication_name,
        'dose_value',i.dose_value,'dose_unit',i.dose_unit,'route',i.route,'frequency',i.frequency,
        'duration_text',i.duration_text,'quantity',i.quantity,'quantity_unit',i.quantity_unit,'repeats',i.repeats,'prn',i.prn
      ) order by i.created_at,i.id)
      from public.prescription_item i where i.prescription_id=v_rx.id
    ),'[]'::jsonb),
    'allergies',coalesce((
      select jsonb_agg(jsonb_build_object('ingredient_id',a.ingredient_id,'substance_text',a.substance_text,'severity',a.severity) order by a.id)
      from public.patient_allergy a where a.practice_id=v_rx.practice_id and a.patient_id=v_rx.patient_id and a.status='active'
    ),'[]'::jsonb),
    'current_medications',coalesce((
      select jsonb_agg(jsonb_build_object('ingredient_id',m.ingredient_id,'product_id',m.product_id,'medication_name',m.medication_name,'dose_text',m.dose_text) order by m.id)
      from public.patient_medication m where m.practice_id=v_rx.practice_id and m.patient_id=v_rx.patient_id and m.status='active'
    ),'[]'::jsonb),
    'reference_ready',v_reference_ready,
    'interaction_ready',v_interaction_ready
  ) into v_payload;

  v_hash:=encode(extensions.digest(v_payload::text,'sha256'),'hex');
  select coalesce(max(assessment_version),0)+1 into v_version
  from public.prescription_safety_assessment where prescription_id=v_rx.id;

  insert into public.prescription_safety_assessment(
    practice_id,prescription_id,assessment_version,status,blocking_count,warning_count,
    reference_ready,interaction_data_ready,assessed_by,input_sha256
  ) values(
    v_rx.practice_id,v_rx.id,v_version,'pass',0,0,v_reference_ready,v_interaction_ready,p_user,v_hash
  ) returning id into v_assessment_id;

  if not exists(select 1 from public.prescription_item where prescription_id=v_rx.id) then
    insert into public.prescription_safety_finding(
      practice_id,assessment_id,finding_type,severity,code,title,detail
    ) values(
      v_rx.practice_id,v_assessment_id,'missing_field','blocking','NO_PRESCRIPTION_ITEMS',
      'Prescription has no medicine items','Add at least one medicine before the prescription can be approved.'
    );
    v_blocking:=v_blocking+1;
  end if;

  if not v_reference_ready then
    insert into public.prescription_safety_finding(
      practice_id,assessment_id,finding_type,severity,code,title,detail
    ) values(
      v_rx.practice_id,v_assessment_id,'reference_data','blocking','MEDICINE_REFERENCE_UNAVAILABLE',
      'Authoritative medicine reference is not active',
      'No activated governed medicine product release is available. Drafting is allowed, but clinician approval and transmission remain blocked.'
    );
    v_blocking:=v_blocking+1;
  end if;

  if not v_interaction_ready then
    insert into public.prescription_safety_finding(
      practice_id,assessment_id,finding_type,severity,code,title,detail
    ) values(
      v_rx.practice_id,v_assessment_id,'reference_data','blocking','INTERACTION_DATA_UNAVAILABLE',
      'Drug-interaction reference is not active',
      'No activated governed interaction dataset is available. PracticeCtrl cannot claim that interaction checking has been completed.'
    );
    v_blocking:=v_blocking+1;
  end if;

  for r in
    select i.* from public.prescription_item i where i.prescription_id=v_rx.id order by i.created_at,i.id
  loop
    if nullif(trim(coalesce(r.medication_name,'')),'') is null then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(v_rx.practice_id,v_assessment_id,r.id,'missing_field','blocking','MEDICINE_NAME_MISSING','Medicine name is missing','Every prescription item requires a medicine name.');
      v_blocking:=v_blocking+1;
    end if;
    if r.dose_value is null or nullif(trim(coalesce(r.dose_unit,'')),'') is null then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(v_rx.practice_id,v_assessment_id,r.id,'missing_field','blocking','DOSE_INCOMPLETE','Dose is incomplete','Dose value and dose unit must be confirmed by the prescriber.');
      v_blocking:=v_blocking+1;
    end if;
    if nullif(trim(coalesce(r.route,'')),'') is null then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(v_rx.practice_id,v_assessment_id,r.id,'missing_field','blocking','ROUTE_MISSING','Route is missing','Administration route must be confirmed by the prescriber.');
      v_blocking:=v_blocking+1;
    end if;
    if nullif(trim(coalesce(r.frequency,'')),'') is null then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(v_rx.practice_id,v_assessment_id,r.id,'missing_field','blocking','FREQUENCY_MISSING','Frequency is missing','Administration frequency must be confirmed by the prescriber.');
      v_blocking:=v_blocking+1;
    end if;
    if nullif(trim(coalesce(r.duration_text,'')),'') is null then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(v_rx.practice_id,v_assessment_id,r.id,'missing_field','warning','DURATION_NOT_RECORDED','Duration is not recorded','Confirm whether a treatment duration/end point is clinically required.');
      v_warning:=v_warning+1;
    end if;
    if r.product_id is null or r.ingredient_id is null then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(v_rx.practice_id,v_assessment_id,r.id,'reference_data','blocking','MEDICINE_NOT_VERIFIED','Medicine is not mapped to governed reference data','Select a governed product and active ingredient before approval.');
      v_blocking:=v_blocking+1;
    end if;

    if r.ingredient_id is not null and exists(
      select 1 from public.patient_allergy a
      where a.practice_id=v_rx.practice_id and a.patient_id=v_rx.patient_id and a.status='active'
        and a.ingredient_id=r.ingredient_id
    ) then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      select v_rx.practice_id,v_assessment_id,r.id,'allergy','blocking','ACTIVE_ALLERGY_MATCH',
        'Active allergy matches prescribed ingredient',
        'Patient allergy record matches the active ingredient: '||a.substance_text||
          case when a.reaction_text is null then '' else ' · reaction: '||a.reaction_text end
      from public.patient_allergy a
      where a.practice_id=v_rx.practice_id and a.patient_id=v_rx.patient_id and a.status='active'
        and a.ingredient_id=r.ingredient_id
      limit 1;
      v_blocking:=v_blocking+1;
    end if;

    if r.ingredient_id is not null and exists(
      select 1 from public.patient_medication m
      where m.practice_id=v_rx.practice_id and m.patient_id=v_rx.patient_id and m.status='active'
        and m.ingredient_id=r.ingredient_id
    ) then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(
        v_rx.practice_id,v_assessment_id,r.id,'duplicate_therapy','warning','ACTIVE_MEDICATION_DUPLICATE',
        'Active medication contains the same ingredient',
        'The medication list already contains this active ingredient. Confirm whether this is continuation, replacement, dose change or unintended duplication.'
      );
      v_warning:=v_warning+1;
    end if;

    if r.ingredient_id is not null and (
      select count(*) from public.prescription_item x
      where x.prescription_id=v_rx.id and x.ingredient_id=r.ingredient_id
    )>1 then
      insert into public.prescription_safety_finding(practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail)
      values(
        v_rx.practice_id,v_assessment_id,r.id,'duplicate_therapy','warning','PRESCRIPTION_INGREDIENT_DUPLICATE',
        'Prescription contains the same ingredient more than once',
        'Confirm whether multiple items containing this ingredient are clinically intentional.'
      );
      v_warning:=v_warning+1;
    end if;
  end loop;

  if v_interaction_ready then
    for r in
      with proposed as (
        select id item_id,ingredient_id from public.prescription_item
        where prescription_id=v_rx.id and ingredient_id is not null
      ),
      current_meds as (
        select null::uuid item_id,ingredient_id from public.patient_medication
        where practice_id=v_rx.practice_id and patient_id=v_rx.patient_id and status='active' and ingredient_id is not null
      ),
      all_meds as (
        select * from proposed union all select * from current_meds
      ),
      pairs as (
        select p.item_id prescription_item_id,p.ingredient_id a,m.ingredient_id b
        from proposed p join all_meds m on m.ingredient_id<>p.ingredient_id
      )
      select distinct p.prescription_item_id,ir.id rule_id,ir.severity,ir.title,ir.description,ir.management_text
      from pairs p
      join public.medicine_interaction_rule ir
        on ir.active
       and least(ir.ingredient_a_id,ir.ingredient_b_id)=least(p.a,p.b)
       and greatest(ir.ingredient_a_id,ir.ingredient_b_id)=greatest(p.a,p.b)
      join public.source_dataset_release rel on rel.id=ir.source_release_id and rel.status='active' and rel.activated_at is not null
      where (ir.effective_from is null or ir.effective_from<=current_date)
        and (ir.effective_to is null or ir.effective_to>=current_date)
    loop
      insert into public.prescription_safety_finding(
        practice_id,assessment_id,prescription_item_id,finding_type,severity,code,title,detail,source_rule_id
      ) values(
        v_rx.practice_id,v_assessment_id,r.prescription_item_id,'interaction',
        case when r.severity in ('major','contraindicated') then 'blocking'
             when r.severity='warning' then 'warning' else 'info' end,
        'SOURCED_DRUG_INTERACTION',r.title,
        r.description||case when nullif(trim(coalesce(r.management_text,'')),'') is null then '' else ' · Management: '||r.management_text end,
        r.rule_id
      );
      if r.severity in ('major','contraindicated') then v_blocking:=v_blocking+1;
      elsif r.severity='warning' then v_warning:=v_warning+1;
      end if;
    end loop;
  end if;

  update public.prescription_safety_assessment
  set blocking_count=v_blocking,warning_count=v_warning,
      status=case when v_blocking>0 then 'block' when v_warning>0 then 'warning' else 'pass' end
  where id=v_assessment_id;

  update public.prescription
  set status=case when v_blocking>0 then 'blocked' else 'safety_review' end,
      safety_assessed_at=now(),updated_at=now()
  where id=v_rx.id;

  return v_assessment_id;
end $function$
;
revoke all on function private.assess_prescription_safety_internal(uuid,uuid) from public, anon;
grant execute on function private.assess_prescription_safety_internal(uuid,uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.add_medication_reconciliation_item(p_session_id uuid, p_existing_medication_id uuid, p_product_id uuid, p_ingredient_id uuid, p_medication_name text, p_dose_text text, p_route text, p_frequency text, p_proposed_action text DEFAULT 'confirm'::text, p_source text DEFAULT 'manual'::text, p_confidence text DEFAULT NULL::text, p_evidence_text text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_session public.medication_reconciliation_session%rowtype; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_session from public.medication_reconciliation_session where id=p_session_id;
  if not found or v_session.status not in ('open','reviewing') then raise exception 'Open reconciliation session required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_session.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;
  if length(trim(coalesce(p_medication_name,'')))<2 then raise exception 'Medication name is required'; end if;
  if p_proposed_action not in ('confirm','add','change','stop','unable_to_verify') then raise exception 'Invalid reconciliation action'; end if;
  if p_source not in ('manual','ai_extracted','document','patient_reported','import') then raise exception 'Invalid reconciliation source'; end if;
  if p_confidence is not null and p_confidence not in ('low','medium','high') then raise exception 'Invalid confidence'; end if;
  if p_existing_medication_id is not null and not exists(
    select 1 from public.patient_medication m
    where m.id=p_existing_medication_id and m.practice_id=v_session.practice_id and m.patient_id=v_session.patient_id
  ) then raise exception 'Existing medication does not belong to this patient/practice'; end if;

  insert into public.medication_reconciliation_item(
    practice_id,session_id,existing_medication_id,product_id,ingredient_id,medication_name,dose_text,route,frequency,
    proposed_action,source,confidence,evidence_text,review_status
  ) values(
    v_session.practice_id,v_session.id,p_existing_medication_id,p_product_id,p_ingredient_id,trim(p_medication_name),
    nullif(trim(coalesce(p_dose_text,'')),''),nullif(trim(coalesce(p_route,'')),''),
    nullif(trim(coalesce(p_frequency,'')),''),
    p_proposed_action,p_source,p_confidence,nullif(trim(coalesce(p_evidence_text,'')),''),'pending'
  ) returning id into v_id;

  update public.medication_reconciliation_session set status='reviewing',updated_at=now() where id=v_session.id;
  return v_id;
end $function$
;
revoke all on function public.add_medication_reconciliation_item(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.add_medication_reconciliation_item(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.apply_medicines_ai_review(p_review_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_review public.medicines_ai_review%rowtype;
  j jsonb;
  v_count integer:=0;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_review from public.medicines_ai_review where id=p_review_id for update;
  if not found then raise exception 'Medicines AI review not found'; end if;
  if v_review.status<>'clinician_accepted' then raise exception 'AI output must be practitioner-accepted before it can be applied'; end if;
  if v_review.applied_at is not null then raise exception 'AI output has already been applied'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_review.practice_id and m.active and m.role='practitioner'
  ) then raise exception 'A practitioner must apply medicines AI output'; end if;

  if v_review.capability_key='medicines.reconciliation_extraction' then
    if v_review.reconciliation_session_id is null then raise exception 'Medication reconciliation session is required'; end if;
    if not exists(
      select 1 from public.medication_reconciliation_session s
      where s.id=v_review.reconciliation_session_id and s.practice_id=v_review.practice_id
        and s.patient_id=v_review.patient_id and s.status in ('open','reviewing')
    ) then raise exception 'Open medication reconciliation session required'; end if;

    for j in select value from jsonb_array_elements(coalesce(v_review.structured_output->'medication_candidates','[]'::jsonb)) loop
      if length(trim(coalesce(j->>'medication_name','')))<2 then continue; end if;
      insert into public.medication_reconciliation_item(
        practice_id,session_id,medication_name,dose_text,route,frequency,proposed_action,source,
        confidence,evidence_text,review_status
      ) values(
        v_review.practice_id,v_review.reconciliation_session_id,trim(j->>'medication_name'),
        nullif(trim(coalesce(j->>'dose_text','')),''),
        nullif(trim(coalesce(j->>'route','')),''),
        nullif(trim(coalesce(j->>'frequency','')),''),
        'add','ai_extracted',
        case when j->>'confidence' in ('low','medium','high') then j->>'confidence' else 'low' end,
        nullif(trim(coalesce(j->>'evidence','')),''),
        'pending'
      );
      v_count:=v_count+1;
    end loop;
    update public.medication_reconciliation_session set status='reviewing',updated_at=now()
    where id=v_review.reconciliation_session_id;

  elsif v_review.capability_key='medicines.prescription_structuring' then
    if v_review.prescription_id is null then raise exception 'Prescription draft is required'; end if;
    if not exists(
      select 1 from public.prescription p
      where p.id=v_review.prescription_id and p.practice_id=v_review.practice_id and p.patient_id=v_review.patient_id
        and p.prescriber_user_id=v_user and p.status in ('draft','safety_review','blocked')
    ) then raise exception 'Editable practitioner-owned prescription draft required'; end if;

    for j in select value from jsonb_array_elements(coalesce(v_review.structured_output->'prescription_items','[]'::jsonb)) loop
      if length(trim(coalesce(j->>'medication_name','')))<2 then continue; end if;
      insert into public.prescription_item(
        practice_id,prescription_id,medication_name,dose_value,dose_unit,route,frequency,duration_text,
        quantity,quantity_unit,repeats,prn,instructions,source
      ) values(
        v_review.practice_id,v_review.prescription_id,trim(j->>'medication_name'),
        case when nullif(j->>'dose_value','') is null then null else (j->>'dose_value')::numeric end,
        nullif(trim(coalesce(j->>'dose_unit','')),''),
        nullif(trim(coalesce(j->>'route','')),''),
        nullif(trim(coalesce(j->>'frequency','')),''),
        nullif(trim(coalesce(j->>'duration_text','')),''),
        case when nullif(j->>'quantity','') is null then null else (j->>'quantity')::numeric end,
        nullif(trim(coalesce(j->>'quantity_unit','')),''),
        greatest(0,least(coalesce((j->>'repeats')::integer,0),12)),
        coalesce((j->>'prn')::boolean,false),
        nullif(trim(coalesce(j->>'instructions','')),''),
        'ai_structured'
      );
      v_count:=v_count+1;
    end loop;
    update public.prescription set status='draft',safety_assessed_at=null,updated_at=now()
    where id=v_review.prescription_id;

  else
    raise exception 'This medicines AI capability is explanatory and has no direct clinical-record apply action';
  end if;

  update public.medicines_ai_review set applied_by=v_user,applied_at=now() where id=v_review.id;

  return jsonb_build_object(
    'review_id',v_review.id,'capability_key',v_review.capability_key,
    'applied_count',v_count,'applied_by',v_user,'applied_at',now(),
    'requires_item_level_review',v_review.capability_key='medicines.reconciliation_extraction',
    'requires_prescription_safety_reassessment',v_review.capability_key='medicines.prescription_structuring'
  );
end $function$
;
revoke all on function public.apply_medicines_ai_review(uuid) from public, anon;
grant execute on function public.apply_medicines_ai_review(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.approve_prescription(p_prescription_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_rx public.prescription%rowtype;
  v_assessment public.prescription_safety_assessment%rowtype;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_rx from public.prescription where id=p_prescription_id for update;
  if not found then raise exception 'Prescription not found'; end if;
  if v_rx.prescriber_user_id<>v_user then raise exception 'Only the prescribing practitioner may approve the prescription'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_rx.practice_id and m.active and m.role='practitioner') then
    raise exception 'Active practitioner role required';
  end if;
  if v_rx.status not in ('draft','safety_review','blocked') then raise exception 'Prescription is not eligible for approval'; end if;

  select private.assess_prescription_safety_internal(v_rx.id,v_user) into v_id;
  select * into v_assessment from public.prescription_safety_assessment where id=v_id;
  if v_assessment.status='block' then
    raise exception 'Prescription approval blocked by deterministic safety findings';
  end if;

  update public.prescription
  set status='clinician_approved',clinician_approved_at=now(),updated_at=now()
  where id=v_rx.id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    v_rx.practice_id,v_rx.patient_id,'prescription',now(),'Prescription clinician-approved',
    'Deterministic safety assessment: '||v_assessment.status||' · warnings '||v_assessment.warning_count::text,
    'prescription',v_rx.id,v_user,'PracticeCtrl',
    jsonb_build_object('assessment_id',v_assessment.id,'status',v_assessment.status,'warning_count',v_assessment.warning_count)
  );

  return jsonb_build_object(
    'prescription_id',v_rx.id,'status','clinician_approved',
    'assessment_id',v_assessment.id,'safety_status',v_assessment.status,'warning_count',v_assessment.warning_count
  );
end $function$
;
revoke all on function public.approve_prescription(uuid) from public, anon;
grant execute on function public.approve_prescription(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.assess_prescription_safety(p_prescription_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_id uuid;
  v_row public.prescription_safety_assessment%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select private.assess_prescription_safety_internal(p_prescription_id,v_user) into v_id;
  select * into v_row from public.prescription_safety_assessment where id=v_id;
  return jsonb_build_object(
    'assessment_id',v_row.id,'status',v_row.status,'blocking_count',v_row.blocking_count,
    'warning_count',v_row.warning_count,'reference_ready',v_row.reference_ready,
    'interaction_data_ready',v_row.interaction_data_ready,'assessed_at',v_row.assessed_at
  );
end $function$
;
revoke all on function public.assess_prescription_safety(uuid) from public, anon;
grant execute on function public.assess_prescription_safety(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.complete_medication_reconciliation(p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_session public.medication_reconciliation_session%rowtype; v_pending integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_session from public.medication_reconciliation_session where id=p_session_id for update;
  if not found or v_session.status not in ('open','reviewing') then raise exception 'Open reconciliation session required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_session.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;
  select count(*) into v_pending from public.medication_reconciliation_item where session_id=v_session.id and review_status='pending';
  if v_pending>0 then raise exception 'Resolve all reconciliation items before completing the session'; end if;

  update public.medication_reconciliation_session
  set status='completed',completed_by=v_user,completed_at=now(),updated_at=now()
  where id=v_session.id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    v_session.practice_id,v_session.patient_id,'medication_reconciliation',now(),'Medication reconciliation completed',
    'Medication list review completed.','medication_reconciliation_session',v_session.id,v_user,'PracticeCtrl',
    jsonb_build_object(
      'accepted',(select count(*) from public.medication_reconciliation_item where session_id=v_session.id and review_status='accepted'),
      'rejected',(select count(*) from public.medication_reconciliation_item where session_id=v_session.id and review_status='rejected')
    )
  );

  return jsonb_build_object('session_id',v_session.id,'status','completed','completed_by',v_user,'completed_at',now());
end $function$
;
revoke all on function public.complete_medication_reconciliation(uuid) from public, anon;
grant execute on function public.complete_medication_reconciliation(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.create_prescription_draft(p_practice_id uuid, p_patient_id uuid, p_encounter_id uuid, p_indication_text text, p_general_instructions text, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_id uuid;
  j jsonb;
  v_name text;
  v_product public.medicine_reference_product%rowtype;
  v_ingredient uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role='practitioner'
  ) then raise exception 'Active practitioner role required'; end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id and p.status='active') then
    raise exception 'Active patient is required';
  end if;
  if p_encounter_id is not null and not exists(
    select 1 from public.practice_encounter e
    where e.id=p_encounter_id and e.practice_id=p_practice_id and e.patient_id=p_patient_id
  ) then raise exception 'Encounter does not belong to this patient/practice'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>30 then
    raise exception 'Provide between 1 and 30 prescription items';
  end if;

  insert into public.prescription(
    practice_id,patient_id,encounter_id,status,issue_mode,indication_text,general_instructions,
    prescriber_user_id,created_by
  ) values(
    p_practice_id,p_patient_id,p_encounter_id,'draft','internal_draft',
    nullif(trim(coalesce(p_indication_text,'')),''),
    nullif(trim(coalesce(p_general_instructions,'')),''),
    v_user,v_user
  ) returning id into v_id;

  for j in select value from jsonb_array_elements(p_items) loop
    v_name:=trim(coalesce(j->>'medication_name',''));
    if length(v_name)<2 then raise exception 'Every prescription item requires a medicine name'; end if;
    v_ingredient:=case when nullif(j->>'ingredient_id','') is null then null else (j->>'ingredient_id')::uuid end;
    if nullif(j->>'product_id','') is not null then
      select * into v_product from public.medicine_reference_product where id=(j->>'product_id')::uuid;
      if not found then raise exception 'Medicine reference product not found'; end if;
      if v_ingredient is null then
        select ingredient_id into v_ingredient
        from public.medicine_product_ingredient where product_id=v_product.id order by sequence_no limit 1;
      end if;
    else
      v_product:=null;
    end if;

    insert into public.prescription_item(
      practice_id,prescription_id,product_id,ingredient_id,medication_name,nappi_code_snapshot,
      dose_value,dose_unit,route,frequency,duration_text,quantity,quantity_unit,repeats,prn,instructions,source
    ) values(
      p_practice_id,v_id,
      case when v_product.id is null then null else v_product.id end,
      v_ingredient,
      v_name,
      case when v_product.id is null then null else v_product.nappi_code end,
      case when nullif(j->>'dose_value','') is null then null else (j->>'dose_value')::numeric end,
      nullif(trim(coalesce(j->>'dose_unit','')),''),
      nullif(trim(coalesce(j->>'route','')),''),
      nullif(trim(coalesce(j->>'frequency','')),''),
      nullif(trim(coalesce(j->>'duration_text','')),''),
      case when nullif(j->>'quantity','') is null then null else (j->>'quantity')::numeric end,
      nullif(trim(coalesce(j->>'quantity_unit','')),''),
      greatest(0,least(coalesce(nullif(j->>'repeats','')::integer,0),12)),
      coalesce((j->>'prn')::boolean,false),
      nullif(trim(coalesce(j->>'instructions','')),''),
      case when j->>'source' in ('manual','ai_structured','reconciliation') then j->>'source' else 'manual' end
    );
  end loop;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    p_practice_id,p_patient_id,'prescription',now(),'Prescription draft created',
    'Draft contains '||jsonb_array_length(p_items)::text||' medicine item(s).',
    'prescription',v_id,v_user,'PracticeCtrl',jsonb_build_object('status','draft')
  );

  return v_id;
end $function$
;
revoke all on function public.create_prescription_draft(uuid,uuid,uuid,text,text,jsonb) from public, anon;
grant execute on function public.create_prescription_draft(uuid,uuid,uuid,text,text,jsonb) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_medicines_ai_readiness(p_practice_id uuid, p_capability_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_policy public.practice_assist_policy%rowtype;
  v_provider public.assist_provider_config%rowtype;
  v_blockers jsonb:='[]'::jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_capability_key not like 'medicines.%' then raise exception 'Medicines AI capability required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active
    and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;

  select * into v_policy from public.practice_assist_policy
  where practice_id=p_practice_id and capability_key=p_capability_key;

  if not found or not v_policy.enabled then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','MEDICINES_AI_POLICY_DISABLED','message','This medicines AI capability is not enabled for the practice.'));
    return jsonb_build_object('ready',false,'capability_key',p_capability_key,'policy_enabled',false,'provider_ready',false,'blockers',v_blockers);
  end if;

  if v_policy.allowed_data_class<>'health_special' or v_policy.retain_raw_input or v_policy.retain_raw_output
     or not v_policy.require_aal2 or not v_policy.human_review_required then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','MEDICINES_AI_POLICY_UNSAFE','message','Practice AI policy does not meet the medicines safety profile.'));
  end if;

  if v_policy.provider_config_id is null then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','MEDICINES_AI_PROVIDER_MISSING','message','No AI provider is selected.'));
  else
    select * into v_provider from public.assist_provider_config where id=v_policy.provider_config_id;
    if not found or v_provider.review_status<>'approved' or not v_provider.transport_ready
       or not v_provider.phi_approved or v_provider.maximum_approved_data_class<>'health_special' then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','MEDICINES_AI_PROVIDER_NOT_READY','message','Selected AI provider is not approved, transport-ready and authorised for health-special information.'));
    end if;
  end if;

  return jsonb_build_object(
    'ready',jsonb_array_length(v_blockers)=0,'capability_key',p_capability_key,
    'policy_enabled',v_policy.enabled,'provider_config_id',v_policy.provider_config_id,
    'model_id',case when v_provider.id is null then null else v_provider.model_id end,
    'human_review_required',true,'raw_input_retained',false,'raw_output_retained',false,'blockers',v_blockers
  );
end $function$
;
revoke all on function public.get_medicines_ai_readiness(uuid,text) from public, anon;
grant execute on function public.get_medicines_ai_readiness(uuid,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_medicines_metrics(p_practice_id uuid, p_window_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_start timestamptz:=now()-make_interval(days=>greatest(1,least(coalesce(p_window_days,30),365)));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active
    and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;
  return jsonb_build_object(
    'active_medications',(select count(*) from public.patient_medication where practice_id=p_practice_id and status='active'),
    'active_allergies',(select count(*) from public.patient_allergy where practice_id=p_practice_id and status='active'),
    'open_reconciliations',(select count(*) from public.medication_reconciliation_session where practice_id=p_practice_id and status in ('open','reviewing')),
    'reconciliations_completed',(select count(*) from public.medication_reconciliation_session where practice_id=p_practice_id and completed_at>=v_start),
    'prescription_drafts',(select count(*) from public.prescription where practice_id=p_practice_id and status in ('draft','safety_review','blocked')),
    'prescriptions_created',(select count(*) from public.prescription where practice_id=p_practice_id and created_at>=v_start),
    'blocked_prescriptions',(select count(*) from public.prescription where practice_id=p_practice_id and status='blocked'),
    'clinician_approved',(select count(*) from public.prescription where practice_id=p_practice_id and clinician_approved_at>=v_start),
    'transmitted',(select count(*) from public.prescription where practice_id=p_practice_id and transmitted_at>=v_start),
    'open_safety_findings',(select count(*) from public.prescription_safety_finding f join public.prescription_safety_assessment a on a.id=f.assessment_id where f.practice_id=p_practice_id and a.assessed_at>=v_start and f.severity='blocking'),
    'ai_reviews',(select count(*) from public.medicines_ai_review where practice_id=p_practice_id and created_at>=v_start)
  );
end $function$
;
revoke all on function public.get_medicines_metrics(uuid,integer) from public, anon;
grant execute on function public.get_medicines_metrics(uuid,integer) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_medicines_readiness(p_practice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_nappi_active int;
  v_sahpra_active int;
  v_products int;
  v_ingredients int;
  v_interactions int;
  v_external_interaction int;
  v_erx_prod int;
  v_erx_sandbox int;
  v_requirements int;
  v_bucket boolean;
  v_blockers jsonb:='[]'::jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active
    and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;

  select count(*) into v_nappi_active
  from public.source_dataset_release r join public.source_dataset d on d.id=r.dataset_id
  where d.dataset_key='nappi_product_price' and r.status='active' and r.activated_at is not null;

  select count(*) into v_sahpra_active
  from public.source_dataset_release r join public.source_dataset d on d.id=r.dataset_id
  where d.dataset_key='sahpra_medicines_directory' and r.status='active' and r.activated_at is not null;

  select count(*) into v_products
  from public.medicine_reference_product p join public.source_dataset_release r on r.id=p.source_release_id
  where p.status='active' and r.status='active' and r.activated_at is not null;

  select count(*) into v_ingredients from public.medicine_reference_ingredient where active;
  select count(*) into v_interactions
  from public.medicine_interaction_rule ir join public.source_dataset_release r on r.id=ir.source_release_id
  where ir.active and r.status='active' and r.activated_at is not null;

  select count(*) into v_external_interaction
  from public.practice_integration_connection c
  join public.integration_adapter_capability ac on ac.provider_id=c.provider_id and ac.interface_id=c.interface_id
  where c.practice_id=p_practice_id and c.status in ('sandbox_active','production_ready','active')
    and ac.capability_code='drug_interaction_check'
    and ((c.environment='sandbox' and ac.executable_sandbox) or (c.environment='production' and ac.executable_production));

  select count(*) into v_erx_prod
  from public.practice_integration_connection c
  join public.integration_adapter_capability ac on ac.provider_id=c.provider_id and ac.interface_id=c.interface_id
  where c.practice_id=p_practice_id and c.environment='production' and c.status in ('production_ready','active')
    and ac.capability_code='prescription_transmit' and ac.executable_production;

  select count(*) into v_erx_sandbox
  from public.practice_integration_connection c
  join public.integration_adapter_capability ac on ac.provider_id=c.provider_id and ac.interface_id=c.interface_id
  where c.practice_id=p_practice_id and c.environment='sandbox' and c.status in ('sandbox_active','active')
    and ac.capability_code='prescription_transmit' and ac.executable_sandbox;

  select count(*) into v_requirements
  from public.integration_requirement r join public.integration_provider p on p.id=r.provider_id
  where p.slug='emguidance-script' and r.status in ('open','in_progress','waiting_external','blocked');

  select exists(select 1 from storage.buckets where id='medicines-ai-files' and public=false) into v_bucket;

  if v_products=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','MEDICINE_REFERENCE_NOT_ACTIVE','scope','clinical_safety','message','No governed medicine product release is active.'));
  end if;
  if v_interactions=0 and v_external_interaction=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','INTERACTION_REFERENCE_NOT_READY','scope','clinical_safety','message','No governed internal interaction dataset or executable external interaction route is available.'));
  end if;
  if v_erx_prod=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','E_PRESCRIBING_PRODUCTION_NOT_READY','scope','production','message','No executable production electronic-prescription route is configured.'));
  end if;
  if v_requirements>0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','E_PRESCRIBING_ONBOARDING_OPEN','scope','production','message',v_requirements||' EMGuidance/e-prescribing onboarding requirements remain open.'));
  end if;
  if not v_bucket then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','MEDICINES_AI_STORAGE_NOT_PRIVATE','scope','ai','message','Medicines AI source storage is not private.'));
  end if;

  return jsonb_build_object(
    'generated_at',now(),'practice_id',p_practice_id,
    'nappi_active_releases',v_nappi_active,'sahpra_active_releases',v_sahpra_active,
    'active_products',v_products,'active_ingredients',v_ingredients,'active_interaction_rules',v_interactions,
    'external_interaction_routes',v_external_interaction,
    'sandbox_erx_routes',v_erx_sandbox,'production_erx_routes',v_erx_prod,
    'open_erx_requirements',v_requirements,'private_ai_storage',v_bucket,
    'drafting_ready',true,
    'deterministic_safety_ready',v_products>0 and (v_interactions>0 or v_external_interaction>0),
    'production_transmission_ready',v_erx_prod>0,
    'blockers',v_blockers
  );
end $function$
;
revoke all on function public.get_medicines_readiness(uuid) from public, anon;
grant execute on function public.get_medicines_readiness(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.queue_prescription_transmission(p_prescription_id uuid, p_provider_id uuid, p_environment text DEFAULT 'production'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp', 'extensions'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_rx public.prescription%rowtype;
  v_connection public.practice_integration_connection%rowtype;
  v_cap public.integration_adapter_capability%rowtype;
  v_id uuid;
  v_key text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_environment not in ('sandbox','production') then raise exception 'Invalid environment'; end if;
  select * into v_rx from public.prescription where id=p_prescription_id for update;
  if not found then raise exception 'Prescription not found'; end if;
  if v_rx.prescriber_user_id<>v_user then raise exception 'Only the prescribing practitioner may transmit this prescription'; end if;
  if v_rx.status<>'clinician_approved' then raise exception 'Prescription must be clinician-approved before transmission'; end if;

  select c.* into v_connection
  from public.practice_integration_connection c
  where c.practice_id=v_rx.practice_id and c.provider_id=p_provider_id
    and c.environment=p_environment and c.status in ('sandbox_active','production_ready','active')
  limit 1;
  if not found then raise exception 'No active prescribing connection exists for this provider/environment'; end if;

  select ac.* into v_cap
  from public.integration_adapter_capability ac
  where ac.provider_id=p_provider_id and ac.interface_id=v_connection.interface_id
    and ac.capability_code='prescription_transmit'
  limit 1;
  if not found then raise exception 'Prescription transmission capability is not registered for this route'; end if;
  if p_environment='sandbox' and not v_cap.executable_sandbox then raise exception 'Prescription transmission is not executable in sandbox'; end if;
  if p_environment='production' and not v_cap.executable_production then raise exception 'Prescription transmission is not executable in production'; end if;

  v_key:=encode(extensions.digest(v_rx.id::text||':'||p_environment||':'||p_provider_id::text,'sha256'),'hex');
  insert into public.prescription_transmission_request(
    practice_id,prescription_id,provider_id,interface_id,connection_id,environment,status,idempotency_key,queued_by
  ) values(
    v_rx.practice_id,v_rx.id,p_provider_id,v_connection.interface_id,v_connection.id,p_environment,'queued',v_key,v_user
  )
  on conflict(prescription_id,environment,idempotency_key)
  do update set status=case when public.prescription_transmission_request.status='failed' then 'queued' else public.prescription_transmission_request.status end
  returning id into v_id;

  update public.prescription
  set status='transmission_pending',issue_mode='electronic',provider_id=p_provider_id,
      interface_id=v_connection.interface_id,connection_id=v_connection.id,updated_at=now()
  where id=v_rx.id;

  insert into public.prescription_transmission_event(practice_id,transmission_request_id,event_type,detail)
  values(v_rx.practice_id,v_id,'queued','Prescription queued through an approved executable PracticeCtrl prescribing route.');

  return jsonb_build_object('transmission_request_id',v_id,'status','queued','environment',p_environment);
end $function$
;
revoke all on function public.queue_prescription_transmission(uuid,uuid,text) from public, anon;
grant execute on function public.queue_prescription_transmission(uuid,uuid,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.record_patient_medication(p_practice_id uuid, p_patient_id uuid, p_product_id uuid, p_ingredient_id uuid, p_medication_name text, p_dose_text text, p_route text, p_frequency text, p_indication_text text, p_start_date date, p_source text DEFAULT 'clinical'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_source not in ('clinical','patient_reported','prescription','reconciliation','document','import','other') then raise exception 'Invalid medication source'; end if;
  if length(trim(coalesce(p_medication_name,'')))<2 then raise exception 'Medication name is required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id and p.status='active') then
    raise exception 'Active patient is required';
  end if;

  insert into public.patient_medication(
    practice_id,patient_id,product_id,ingredient_id,medication_name,dose_text,route,frequency,indication_text,
    status,start_date,source,reconciled,reconciled_by,reconciled_at,created_by
  ) values(
    p_practice_id,p_patient_id,p_product_id,p_ingredient_id,trim(p_medication_name),
    nullif(trim(coalesce(p_dose_text,'')),''),nullif(trim(coalesce(p_route,'')),''),
    nullif(trim(coalesce(p_frequency,'')),''),nullif(trim(coalesce(p_indication_text,'')),''),
    'active',coalesce(p_start_date,current_date),p_source,
    p_source='reconciliation',case when p_source='reconciliation' then v_user else null end,
    case when p_source='reconciliation' then now() else null end,v_user
  ) returning id into v_id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    p_practice_id,p_patient_id,'medication',now(),'Medication recorded',
    trim(p_medication_name),'patient_medication',v_id,v_user,'PracticeCtrl',jsonb_build_object('source',p_source,'status','active')
  );
  return v_id;
end $function$
;
revoke all on function public.record_patient_medication(uuid,uuid,uuid,uuid,text,text,text,text,text,date,text) from public, anon;
grant execute on function public.record_patient_medication(uuid,uuid,uuid,uuid,text,text,text,text,text,date,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.review_medication_reconciliation_item(p_item_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_item public.medication_reconciliation_item%rowtype;
  v_session public.medication_reconciliation_session%rowtype;
  v_medication_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_decision not in ('accept','reject') then raise exception 'Decision must be accept or reject'; end if;
  select * into v_item from public.medication_reconciliation_item where id=p_item_id for update;
  if not found or v_item.review_status<>'pending' then raise exception 'Pending reconciliation item required'; end if;
  select * into v_session from public.medication_reconciliation_session where id=v_item.session_id;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_item.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;

  if p_decision='accept' then
    if v_item.proposed_action='add' then
      insert into public.patient_medication(
        practice_id,patient_id,product_id,ingredient_id,medication_name,dose_text,route,frequency,status,
        source,reconciled,reconciled_by,reconciled_at,created_by
      ) values(
        v_item.practice_id,v_session.patient_id,v_item.product_id,v_item.ingredient_id,v_item.medication_name,
        v_item.dose_text,v_item.route,v_item.frequency,'active','reconciliation',true,v_user,now(),v_user
      ) returning id into v_medication_id;
    elsif v_item.proposed_action in ('confirm','change') and v_item.existing_medication_id is not null then
      update public.patient_medication
      set product_id=coalesce(v_item.product_id,product_id),
          ingredient_id=coalesce(v_item.ingredient_id,ingredient_id),
          medication_name=coalesce(nullif(trim(v_item.medication_name),''),medication_name),
          dose_text=case when v_item.proposed_action='change' then coalesce(v_item.dose_text,dose_text) else dose_text end,
          route=case when v_item.proposed_action='change' then coalesce(v_item.route,route) else route end,
          frequency=case when v_item.proposed_action='change' then coalesce(v_item.frequency,frequency) else frequency end,
          reconciled=true,reconciled_by=v_user,reconciled_at=now(),updated_at=now()
      where id=v_item.existing_medication_id
      returning id into v_medication_id;
    elsif v_item.proposed_action='stop' and v_item.existing_medication_id is not null then
      update public.patient_medication
      set status='stopped',end_date=coalesce(end_date,current_date),reconciled=true,reconciled_by=v_user,reconciled_at=now(),updated_at=now()
      where id=v_item.existing_medication_id
      returning id into v_medication_id;
    end if;
  end if;

  update public.medication_reconciliation_item
  set review_status=case when p_decision='accept' then 'accepted' else 'rejected' end,
      reviewed_by=v_user,reviewed_at=now()
  where id=v_item.id;

  return jsonb_build_object(
    'item_id',v_item.id,'decision',p_decision,'review_status',
    case when p_decision='accept' then 'accepted' else 'rejected' end,
    'patient_medication_id',v_medication_id
  );
end $function$
;
revoke all on function public.review_medication_reconciliation_item(uuid,text) from public, anon;
grant execute on function public.review_medication_reconciliation_item(uuid,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.review_medicines_ai_output(p_review_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_review public.medicines_ai_review%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_decision not in ('accept','discard') then raise exception 'Decision must be accept or discard'; end if;
  select * into v_review from public.medicines_ai_review where id=p_review_id for update;
  if not found or v_review.status<>'completed' then raise exception 'Completed medicines AI review required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_review.practice_id and m.active and m.role='practitioner') then
    raise exception 'A practitioner must review medicines AI output';
  end if;

  update public.medicines_ai_review
  set status=case when p_decision='accept' then 'clinician_accepted' else 'discarded' end,
      reviewed_by=v_user,reviewed_at=now()
  where id=v_review.id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    v_review.practice_id,v_review.patient_id,'medication',now(),
    case when p_decision='accept' then 'AI-assisted medicines output reviewed' else 'AI-assisted medicines output discarded' end,
    left(coalesce(v_review.summary,'Medicines AI output reviewed.'),1000),
    case when v_review.prescription_id is not null then 'prescription' else 'medication_reconciliation_session' end,
    coalesce(v_review.prescription_id,v_review.reconciliation_session_id),v_user,'PracticeCtrl',
    jsonb_build_object('ai_review_id',v_review.id,'capability_key',v_review.capability_key,'decision',p_decision,'human_reviewed',true)
  );

  return jsonb_build_object(
    'review_id',v_review.id,'status',case when p_decision='accept' then 'clinician_accepted' else 'discarded' end,
    'reviewed_by',v_user,'reviewed_at',now()
  );
end $function$
;
revoke all on function public.review_medicines_ai_output(uuid,text) from public, anon;
grant execute on function public.review_medicines_ai_output(uuid,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.search_medicine_reference(p_query text, p_limit integer DEFAULT 20)
 RETURNS TABLE(product_id uuid, nappi_code text, sahpra_registration_no text, product_name text, active_ingredient_text text, strength_text text, dosage_form text, route_text text, schedule_text text, manufacturer text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_q text:=trim(coalesce(p_query,''));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(v_q)<2 then return; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.active) then
    raise exception 'Active practice membership required';
  end if;
  return query
  select p.id,p.nappi_code,p.sahpra_registration_no,p.product_name,p.active_ingredient_text,
         p.strength_text,p.dosage_form,p.route_text,p.schedule_text,p.manufacturer
  from public.medicine_reference_product p
  join public.source_dataset_release rel on rel.id=p.source_release_id
  where p.status='active' and rel.status='active' and rel.activated_at is not null
    and (
      p.product_name ilike '%'||v_q||'%'
      or coalesce(p.proprietary_name,'') ilike '%'||v_q||'%'
      or coalesce(p.active_ingredient_text,'') ilike '%'||v_q||'%'
      or coalesce(p.nappi_code,'')=v_q
      or coalesce(p.sahpra_registration_no,'')=v_q
    )
  order by case when lower(p.product_name)=lower(v_q) then 0 when p.nappi_code=v_q then 1 else 2 end,p.product_name
  limit greatest(1,least(coalesce(p_limit,20),100));
end $function$
;
revoke all on function public.search_medicine_reference(text,integer) from public, anon;
grant execute on function public.search_medicine_reference(text,integer) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.start_medication_reconciliation(p_practice_id uuid, p_patient_id uuid, p_encounter_id uuid DEFAULT NULL::uuid, p_source_context text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id and p.status='active') then
    raise exception 'Active patient is required';
  end if;
  if p_encounter_id is not null and not exists(
    select 1 from public.practice_encounter e where e.id=p_encounter_id and e.practice_id=p_practice_id and e.patient_id=p_patient_id
  ) then raise exception 'Encounter does not belong to this patient/practice'; end if;

  insert into public.medication_reconciliation_session(
    practice_id,patient_id,encounter_id,status,source_context,started_by
  ) values(
    p_practice_id,p_patient_id,p_encounter_id,'open',nullif(trim(coalesce(p_source_context,'')),''),v_user
  ) returning id into v_id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    p_practice_id,p_patient_id,'medication_reconciliation',now(),'Medication reconciliation started',
    coalesce(nullif(trim(coalesce(p_source_context,'')),''),'Medication list reconciliation opened.'),
    'medication_reconciliation_session',v_id,v_user,'PracticeCtrl','{}'::jsonb
  );

  return v_id;
end $function$
;
revoke all on function public.start_medication_reconciliation(uuid,uuid,uuid,text) from public, anon;
grant execute on function public.start_medication_reconciliation(uuid,uuid,uuid,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.stop_patient_medication(p_medication_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_med public.patient_medication%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_med from public.patient_medication where id=p_medication_id for update;
  if not found then raise exception 'Medication not found'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_med.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;
  update public.patient_medication
  set status='stopped',end_date=coalesce(end_date,current_date),updated_at=now()
  where id=v_med.id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    v_med.practice_id,v_med.patient_id,'medication',now(),'Medication stopped',
    v_med.medication_name||case when nullif(trim(coalesce(p_reason,'')),'') is null then '' else ' · '||trim(p_reason) end,
    'patient_medication',v_med.id,v_user,'PracticeCtrl','{}'::jsonb
  );
  return jsonb_build_object('medication_id',v_med.id,'status','stopped','stopped_at',now());
end $function$
;
revoke all on function public.stop_patient_medication(uuid,text) from public, anon;
grant execute on function public.stop_patient_medication(uuid,text) to authenticated, service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('medicines-ai-files','medicines-ai-files',false,10485760,array['application/pdf','image/jpeg','image/png']) on conflict(id) do nothing;
create policy "medicines_ai_files_delete" on storage.objects for delete to authenticated using (((bucket_id = 'medicines-ai-files'::text) AND ((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = ((storage.foldername(objects.name))[1])::uuid) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "medicines_ai_files_insert" on storage.objects for insert to authenticated with check (((bucket_id = 'medicines-ai-files'::text) AND ((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = ((storage.foldername(objects.name))[1])::uuid) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "medicines_ai_files_read" on storage.objects for select to authenticated using (((bucket_id = 'medicines-ai-files'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = ((storage.foldername(objects.name))[1])::uuid) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role])))))));
commit;
