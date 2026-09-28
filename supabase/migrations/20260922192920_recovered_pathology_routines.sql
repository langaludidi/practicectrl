-- Recovered pathology routines, private storage and sandbox integration fixtures.
-- Schema and governed reference configuration only; no patient data or credentials are copied.
begin;
insert into public.integration_provider(slug,name,provider_type,lifecycle_status) values ('practicectrl-pathology-sandbox','PracticeCtrl Pathology Sandbox','pathology_lab','sandbox_active') on conflict(slug) do nothing;
insert into public.integration_interface(provider_id,name,interface_type,direction,sync_mode,status) select id,'PracticeCtrl deterministic pathology sandbox','api','bidirectional','realtime','sandbox_active' from public.integration_provider where slug='practicectrl-pathology-sandbox' on conflict(provider_id,name) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('pathology_order_submit','Pathology order submission','clinical','Submit a pathology test order to a laboratory or internal sandbox route.',true,true) on conflict(code) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('pathology_report_document','Pathology report document','clinical','Receive or retrieve a signed pathology report document.',true,true) on conflict(code) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('pathology_result_query','Pathology result query','clinical','Query laboratory order/result status where supported.',true,true) on conflict(code) do nothing;
insert into public.integration_capability_catalog(code,display_name,domain,description,requires_patient_context,transactional) values ('pathology_result_receive','Pathology result receipt','clinical','Receive structured pathology results and result status updates.',true,true) on conflict(code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'pathology_order_submit','conformance_passed',true,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='practicectrl-pathology-sandbox' and i.name='PracticeCtrl deterministic pathology sandbox' on conflict(provider_id,interface_id,capability_code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'pathology_report_document','mapping',false,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='practicectrl-pathology-sandbox' and i.name='PracticeCtrl deterministic pathology sandbox' on conflict(provider_id,interface_id,capability_code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'pathology_result_query','mapping',false,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='practicectrl-pathology-sandbox' and i.name='PracticeCtrl deterministic pathology sandbox' on conflict(provider_id,interface_id,capability_code) do nothing;
insert into public.integration_adapter_capability(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production) select p.id,i.id,'pathology_result_receive','mapping',false,false from public.integration_provider p join public.integration_interface i on i.provider_id=p.id where p.slug='practicectrl-pathology-sandbox' and i.name='PracticeCtrl deterministic pathology sandbox' on conflict(provider_id,interface_id,capability_code) do nothing;

CREATE OR REPLACE FUNCTION private.process_pathology_safety_escalations()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  r record;
  v_next integer;
  v_manager uuid;
  v_count integer:=0;
  v_manager_items integer:=0;
begin
  for r in
    select c.*,res.overall_flag,res.order_id,res.patient_id
    from public.pathology_safety_case c
    join public.pathology_result res on res.id=c.result_id
    where c.status='open'
      and res.is_current
      and res.status in ('final','corrected')
      and (
        (c.escalation_level=0 and now()>=c.sla_due_at)
        or (c.escalation_level=1 and now()>=c.sla_due_at+case c.severity when 'critical' then interval '1 hour' when 'abnormal' then interval '12 hours' else interval '24 hours' end)
        or (c.escalation_level=2 and now()>=c.sla_due_at+case c.severity when 'critical' then interval '3 hours' when 'abnormal' then interval '24 hours' else interval '48 hours' end)
      )
    order by c.sla_due_at
    limit 100
    for update of c skip locked
  loop
    v_next:=least(r.escalation_level+1,3);

    update public.pathology_safety_case
    set escalation_level=v_next,last_escalated_at=now(),updated_at=now()
    where id=r.id;

    insert into public.pathology_safety_event(practice_id,safety_case_id,event_type,escalation_level,detail)
    values(r.practice_id,r.id,'escalated',v_next,
      'Pathology review SLA exceeded; escalation level '||v_next::text||' applied.');

    update public.operations_work_item
    set breached_at=coalesce(breached_at,now()),
        priority=case when r.severity='critical' or v_next>=2 then 'urgent' else priority end,
        title=case when title like 'OVERDUE:%' then title else 'OVERDUE: '||title end,
        updated_at=now()
    where practice_id=r.practice_id and source_entity_type='pathology_result' and source_entity_id=r.result_id
      and category='pathology' and status in ('open','in_progress','waiting','blocked');

    if v_next>=2 then
      select user_id into v_manager
      from public.practice_staff_member
      where practice_id=r.practice_id and active and role in ('practice_manager','system_admin')
      order by case role when 'practice_manager' then 0 else 1 end,created_at
      limit 1;

      insert into public.operations_work_item(
        practice_id,patient_id,category,source_entity_type,source_entity_id,title,description,priority,status,owner_user_id,due_at
      ) values(
        r.practice_id,r.patient_id,'pathology','pathology_safety_case',r.id,
        case when r.severity='critical' then 'Escalated critical pathology result is overdue' else 'Escalated pathology review is overdue' end,
        'The treating clinical review SLA has been breached. Ensure a qualified clinician reviews and documents action without delay.',
        'urgent','open',v_manager,now()+interval '1 hour'
      )
      on conflict(practice_id,source_entity_type,source_entity_id,category) where source_entity_id is not null
      do update set status='open',owner_user_id=coalesce(public.operations_work_item.owner_user_id,excluded.owner_user_id),
                    priority='urgent',due_at=excluded.due_at,updated_at=now();
      v_manager_items:=v_manager_items+1;
    end if;
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object('escalated_cases',v_count,'manager_escalations',v_manager_items,'processed_at',now());
end $function$
;
revoke all on function private.process_pathology_safety_escalations() from public, anon;
CREATE OR REPLACE FUNCTION private.resolve_pathology_concept(p_provider_id uuid, p_test_code text, p_test_name text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  select m.concept_id
  from public.pathology_provider_test_mapping m
  where m.provider_id=p_provider_id
    and m.mapping_status='verified'
    and (
      (nullif(trim(p_test_code),'') is not null and m.provider_test_code=trim(p_test_code))
      or (
        nullif(trim(p_test_code),'') is null
        and m.provider_test_code is null
        and lower(trim(m.provider_test_name))=lower(trim(coalesce(p_test_name,'')))
      )
    )
    and (m.effective_from is null or m.effective_from<=current_date)
    and (m.effective_to is null or m.effective_to>=current_date)
  order by case when m.provider_test_code is not null then 0 else 1 end,coalesce(m.verified_at,m.created_at) desc
  limit 1
$function$
;
revoke all on function private.resolve_pathology_concept(uuid,text,text) from public, anon;
CREATE OR REPLACE FUNCTION private.seed_pathology_release_policy(p_practice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
  insert into public.pathology_release_policy(practice_id)
  values(p_practice_id)
  on conflict(practice_id) do nothing;
end $function$
;
revoke all on function private.seed_pathology_release_policy(uuid) from public, anon;
CREATE OR REPLACE FUNCTION private.seed_pathology_release_policy_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin perform private.seed_pathology_release_policy(new.id); return new; end $function$
;
revoke all on function private.seed_pathology_release_policy_trigger() from public, anon;
CREATE OR REPLACE FUNCTION private.seed_pathology_sandbox_connection(p_practice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_provider uuid; v_interface uuid;
begin
  select p.id,i.id into v_provider,v_interface
  from public.integration_provider p
  join public.integration_interface i on i.provider_id=p.id
  where p.slug='practicectrl-pathology-sandbox'
    and i.name='PracticeCtrl deterministic pathology sandbox'
  limit 1;

  if v_provider is null or v_interface is null then return; end if;

  insert into public.practice_integration_connection(
    practice_id,provider_id,interface_id,environment,status,configuration
  ) values(
    p_practice_id,v_provider,v_interface,'sandbox','sandbox_active',
    jsonb_build_object('synthetic_only',true,'clinical_truth',false,'contract_version','pc-pathology-v1')
  )
  on conflict(practice_id,provider_id,interface_id,environment)
  do update set status='sandbox_active',configuration=excluded.configuration,updated_at=now();
end $function$
;
revoke all on function private.seed_pathology_sandbox_connection(uuid) from public, anon;
CREATE OR REPLACE FUNCTION private.seed_pathology_sandbox_connection_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
  perform private.seed_pathology_sandbox_connection(new.id);
  return new;
end $function$
;
revoke all on function private.seed_pathology_sandbox_connection_trigger() from public, anon;
CREATE OR REPLACE FUNCTION public.acknowledge_pathology_result(p_result_id uuid, p_acknowledgement_status text DEFAULT 'acknowledged'::text, p_follow_up_plan text DEFAULT NULL::text, p_patient_contacted_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_result public.pathology_result%rowtype;
  v_case_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_acknowledgement_status not in ('acknowledged','action_required','follow_up_arranged','patient_contacted') then
    raise exception 'Invalid acknowledgement status';
  end if;

  select * into v_result from public.pathology_result where id=p_result_id;
  if not found then raise exception 'Pathology result not found'; end if;
  if not v_result.is_current or v_result.status not in ('final','corrected') then
    raise exception 'Only the current final/corrected result can be acknowledged';
  end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_result.practice_id and m.active and m.role in ('practitioner','clinical_admin')
  ) then raise exception 'Clinical write role required'; end if;

  insert into public.pathology_result_acknowledgement(
    practice_id,result_id,acknowledgement_status,follow_up_plan,patient_contacted_at,acknowledged_by,acknowledged_at,updated_at
  ) values(
    v_result.practice_id,v_result.id,p_acknowledgement_status,nullif(trim(coalesce(p_follow_up_plan,'')),''),
    p_patient_contacted_at,v_user,now(),now()
  )
  on conflict(result_id) do update set
    acknowledgement_status=excluded.acknowledgement_status,
    follow_up_plan=excluded.follow_up_plan,
    patient_contacted_at=excluded.patient_contacted_at,
    acknowledged_by=v_user,
    acknowledged_at=now(),
    updated_at=now();

  update public.operations_work_item
  set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
  where practice_id=v_result.practice_id and category='pathology'
    and source_entity_type='pathology_result' and source_entity_id=v_result.id
    and status in ('open','in_progress','waiting','blocked');

  update public.pathology_safety_case
  set status='resolved',acknowledged_at=coalesce(acknowledged_at,now()),resolved_at=now(),updated_at=now()
  where result_id=v_result.id and status in ('open','acknowledged')
  returning id into v_case_id;

  if v_case_id is not null then
    insert into public.pathology_safety_event(practice_id,safety_case_id,event_type,escalation_level,detail,actor_user_id)
    select v_result.practice_id,v_case_id,'resolved',c.escalation_level,
           'Clinician acknowledged the current pathology result.',v_user
    from public.pathology_safety_case c where c.id=v_case_id;

    update public.operations_work_item
    set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
    where practice_id=v_result.practice_id and source_entity_type='pathology_safety_case' and source_entity_id=v_case_id
      and category='pathology' and status in ('open','in_progress','waiting','blocked');
  end if;

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(v_result.practice_id,v_result.patient_id,'result',v_result.id,'result_acknowledged',v_user,
    jsonb_build_object('status',p_acknowledgement_status,'patient_contacted_at',p_patient_contacted_at,'safety_case_id',v_case_id));

  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(v_result.practice_id,v_result.patient_id,'pathology_review',now(),'Pathology result reviewed',
    replace(p_acknowledgement_status,'_',' '),'pathology_result',v_result.id,v_user,'PracticeCtrl',
    jsonb_build_object('follow_up_plan_recorded',nullif(trim(coalesce(p_follow_up_plan,'')),'') is not null,'version_no',v_result.version_no));

  return jsonb_build_object('result_id',v_result.id,'acknowledgement_status',p_acknowledgement_status,'acknowledged_by',v_user,'acknowledged_at',now(),'safety_case_id',v_case_id);
end $function$
;
revoke all on function public.acknowledge_pathology_result(uuid,text,text,timestamp with time zone) from public, anon;
grant execute on function public.acknowledge_pathology_result(uuid,text,text,timestamp with time zone) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.approve_pathology_result_for_patient(p_result_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_result public.pathology_result%rowtype;
  v_ack public.pathology_result_acknowledgement%rowtype;
  v_policy public.pathology_release_policy%rowtype;
  v_release_after timestamptz;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_result from public.pathology_result where id=p_result_id;
  if not found then raise exception 'Pathology result not found'; end if;
  if not v_result.is_current or v_result.status not in ('final','corrected') then
    raise exception 'Only the current final/corrected result can be approved for patient release';
  end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_result.practice_id and m.active and m.role='practitioner'
  ) then raise exception 'A practitioner must approve patient release'; end if;

  select * into v_ack from public.pathology_result_acknowledgement where result_id=v_result.id;
  if not found then raise exception 'Clinician acknowledgement is required before patient release approval'; end if;
  if v_result.overall_flag='critical'
     and coalesce(nullif(trim(v_ack.follow_up_plan),''),'')=''
     and v_ack.acknowledgement_status not in ('follow_up_arranged','patient_contacted') then
    raise exception 'Critical results require a documented follow-up plan or patient contact before release approval';
  end if;

  select * into v_policy from public.pathology_release_policy where practice_id=v_result.practice_id;
  v_release_after:=case
    when v_policy.default_mode='delayed_after_review' and v_policy.minimum_delay_minutes>0
    then now()+make_interval(mins=>v_policy.minimum_delay_minutes)
    else now()
  end;

  insert into public.pathology_result_release(practice_id,result_id,status,hold_reason,release_after,approved_by,approved_at,updated_at)
  values(v_result.practice_id,v_result.id,'approved',null,v_release_after,v_user,now(),now())
  on conflict(result_id) do update set
    status='approved',hold_reason=null,release_after=excluded.release_after,
    approved_by=v_user,approved_at=now(),updated_at=now();

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(v_result.practice_id,v_result.patient_id,'result',v_result.id,'patient_release_approved',v_user,
    jsonb_build_object('release_after',v_release_after,'overall_flag',v_result.overall_flag));

  return jsonb_build_object('result_id',v_result.id,'status','approved','release_after',v_release_after,'approved_by',v_user);
end $function$
;
revoke all on function public.approve_pathology_result_for_patient(uuid) from public, anon;
grant execute on function public.approve_pathology_result_for_patient(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.complete_pathology_follow_up_action(p_action_id uuid, p_completion_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_action public.pathology_follow_up_action%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_action from public.pathology_follow_up_action where id=p_action_id for update;
  if not found then raise exception 'Pathology follow-up action not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_action.practice_id and m.active and m.role in ('practitioner','clinical_admin')
  ) then raise exception 'Clinical write role required'; end if;

  update public.pathology_follow_up_action
  set status='completed',details=case when nullif(trim(coalesce(p_completion_note,'')),'') is null then details else concat_ws(E'\n',details,'Completion: '||trim(p_completion_note)) end,
      completed_by=v_user,completed_at=now(),updated_at=now()
  where id=v_action.id;

  update public.operations_work_item
  set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
  where practice_id=v_action.practice_id and source_entity_type='pathology_follow_up_action' and source_entity_id=v_action.id
    and category='patient_follow_up' and status in ('open','in_progress','waiting','blocked');

  return jsonb_build_object('action_id',v_action.id,'status','completed','completed_by',v_user,'completed_at',now());
end $function$
;
revoke all on function public.complete_pathology_follow_up_action(uuid,text) from public, anon;
grant execute on function public.complete_pathology_follow_up_action(uuid,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.create_pathology_follow_up_action(p_result_id uuid, p_action_type text, p_due_at timestamp with time zone, p_details text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_result public.pathology_result%rowtype;
  v_patient public.crm_patient%rowtype;
  v_id uuid;
  v_appt uuid;
  v_priority text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_action_type not in ('patient_contact','repeat_pathology','consultation','referral','medication_review','other') then
    raise exception 'Invalid pathology follow-up action';
  end if;
  select * into v_result from public.pathology_result where id=p_result_id;
  if not found then raise exception 'Pathology result not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_result.practice_id and m.active and m.role in ('practitioner','clinical_admin')
  ) then raise exception 'Clinical write role required'; end if;
  select * into v_patient from public.crm_patient where id=v_result.patient_id;

  if p_action_type='consultation' then
    insert into public.appointment_request(
      practice_id,patient_id,source,requester_name,requester_phone,requester_email,requested_service,preferred_date,message,status,created_by
    ) values(
      v_result.practice_id,v_result.patient_id,'internal',coalesce(v_patient.display_name,'Patient'),
      v_patient.primary_phone,v_patient.primary_email,'Pathology follow-up',
      p_due_at::date,
      'Follow-up requested from pathology result '||v_result.id::text||case when nullif(trim(coalesce(p_details,'')),'') is null then '' else ': '||trim(p_details) end,
      'New',v_user
    ) returning id into v_appt;
  end if;

  insert into public.pathology_follow_up_action(
    practice_id,patient_id,result_id,action_type,status,due_at,details,appointment_request_id,created_by
  ) values(
    v_result.practice_id,v_result.patient_id,v_result.id,p_action_type,'planned',p_due_at,
    nullif(trim(coalesce(p_details,'')),''),v_appt,v_user
  ) returning id into v_id;

  v_priority:=case when v_result.overall_flag='critical' then 'urgent' when v_result.overall_flag='abnormal' then 'high' else 'normal' end;

  insert into public.operations_work_item(
    practice_id,patient_id,category,source_entity_type,source_entity_id,title,description,priority,status,due_at,created_by
  ) values(
    v_result.practice_id,v_result.patient_id,'patient_follow_up','pathology_follow_up_action',v_id,
    'Pathology follow-up: '||replace(p_action_type,'_',' '),
    coalesce(nullif(trim(coalesce(p_details,'')),''),'Complete the documented pathology follow-up action.'),
    v_priority,'open',p_due_at,v_user
  )
  on conflict(practice_id,source_entity_type,source_entity_id,category) where source_entity_id is not null
  do nothing;

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(v_result.practice_id,v_result.patient_id,'result',v_result.id,'follow_up_action_created',v_user,
    jsonb_build_object('follow_up_action_id',v_id,'action_type',p_action_type,'due_at',p_due_at,'appointment_request_id',v_appt));

  return v_id;
end $function$
;
revoke all on function public.create_pathology_follow_up_action(uuid,text,timestamp with time zone,text) from public, anon;
grant execute on function public.create_pathology_follow_up_action(uuid,text,timestamp with time zone,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.create_pathology_order(p_practice_id uuid, p_patient_id uuid, p_encounter_id uuid, p_provider_id uuid, p_order_category text, p_priority text, p_clinical_indication text, p_fasting_required boolean, p_patient_instructions text, p_tests jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_role public.practice_staff_role;
  v_id uuid;
  v_order_no text;
  v_test jsonb;
  v_test_name text;
  v_treating uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_order_category not in ('routine_lab','microbiology','molecular','cytology','histology','biopsy','genetic','other') then raise exception 'Invalid pathology category'; end if;
  if p_priority not in ('routine','urgent','stat') then raise exception 'Invalid pathology priority'; end if;
  if jsonb_typeof(p_tests)<>'array' or jsonb_array_length(p_tests)<1 or jsonb_array_length(p_tests)>50 then
    raise exception 'Provide between 1 and 50 requested pathology tests';
  end if;

  select role into v_role from public.practice_staff_member
  where user_id=v_user and practice_id=p_practice_id and active;
  if v_role not in ('practitioner','clinical_admin') then raise exception 'Clinical write role required'; end if;

  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id and p.status='active') then
    raise exception 'Patient is not active in this practice';
  end if;
  if p_encounter_id is not null then
    select practitioner_user_id into v_treating
    from public.practice_encounter e
    where e.id=p_encounter_id and e.practice_id=p_practice_id and e.patient_id=p_patient_id;
    if not found then raise exception 'Encounter does not belong to this patient/practice'; end if;
  end if;
  if v_treating is null and v_role='practitioner' then v_treating:=v_user; end if;

  if not exists(
    select 1 from public.integration_provider p where p.id=p_provider_id and p.provider_type='pathology_lab' and p.lifecycle_status<>'retired'
  ) then raise exception 'Registered pathology provider required'; end if;

  v_order_no:='PATH-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

  insert into public.pathology_order(
    practice_id,patient_id,encounter_id,provider_id,order_number,status,order_category,priority,clinical_indication,
    fasting_required,patient_instructions,treating_practitioner_user_id,created_by
  ) values(
    p_practice_id,p_patient_id,p_encounter_id,p_provider_id,v_order_no,'draft',p_order_category,p_priority,
    nullif(trim(coalesce(p_clinical_indication,'')),''),
    p_fasting_required,nullif(trim(coalesce(p_patient_instructions,'')),''),v_treating,v_user
  ) returning id into v_id;

  for v_test in select value from jsonb_array_elements(p_tests) loop
    v_test_name:=trim(coalesce(v_test->>'test_name',''));
    if length(v_test_name)<2 then raise exception 'Every requested test requires a name'; end if;
    insert into public.pathology_order_item(
      practice_id,order_id,test_code,test_name,specimen_type,instructions
    ) values(
      p_practice_id,v_id,nullif(trim(coalesce(v_test->>'test_code','')),''),
      v_test_name,nullif(trim(coalesce(v_test->>'specimen_type','')),''),
      nullif(trim(coalesce(v_test->>'instructions','')),'')
    );
  end loop;

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(p_practice_id,p_patient_id,'order',v_id,'draft_created',v_user,
    jsonb_build_object('priority',p_priority,'order_category',p_order_category,'test_count',jsonb_array_length(p_tests),'treating_practitioner_user_id',v_treating));

  return v_id;
end $function$
;
revoke all on function public.create_pathology_order(uuid,uuid,uuid,uuid,text,text,text,boolean,text,jsonb) from public, anon;
grant execute on function public.create_pathology_order(uuid,uuid,uuid,uuid,text,text,text,boolean,text,jsonb) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.create_pathology_specimen(p_order_id uuid, p_specimen_type text, p_specimen_identifier text DEFAULT NULL::text, p_body_site text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_order public.pathology_order%rowtype; v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_specimen_type,'')))<2 then raise exception 'Specimen type is required'; end if;
  select * into v_order from public.pathology_order where id=p_order_id;
  if not found then raise exception 'Pathology order not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_order.practice_id and m.active and m.role in ('practitioner','clinical_admin')
  ) then raise exception 'Clinical write role required'; end if;

  insert into public.pathology_specimen(
    practice_id,order_id,patient_id,specimen_identifier,specimen_type,body_site,status,created_by
  ) values(
    v_order.practice_id,v_order.id,v_order.patient_id,
    nullif(trim(coalesce(p_specimen_identifier,'')),''),
    trim(p_specimen_type),nullif(trim(coalesce(p_body_site,'')),''),
    'ordered',v_user
  ) returning id into v_id;

  insert into public.pathology_specimen_event(practice_id,specimen_id,from_status,to_status,note,actor_user_id)
  values(v_order.practice_id,v_id,null,'ordered','Specimen tracking opened.',v_user);
  return v_id;
end $function$
;
revoke all on function public.create_pathology_specimen(uuid,text,text,text) from public, anon;
grant execute on function public.create_pathology_specimen(uuid,text,text,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.file_pathology_result_inbox(p_inbox_id uuid, p_status text, p_reported_at timestamp with time zone, p_report_comment text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_row public.pathology_result_inbox%rowtype;
  v_order uuid;
  v_result uuid;
  v_duplicate uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_row from public.pathology_result_inbox where id=p_inbox_id for update;
  if not found then raise exception 'Pathology inbox result not found'; end if;
  if v_row.status not in ('patient_matched','order_matched') or v_row.patient_id is null then
    raise exception 'Confirm the patient before filing an unsolicited pathology result';
  end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_row.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;

  if v_row.external_result_ref is not null then
    select id into v_duplicate from public.pathology_result
    where provider_id=v_row.provider_id and external_result_ref=v_row.external_result_ref and is_current
    limit 1;
    if v_duplicate is not null then
      update public.pathology_result_inbox
      set status='duplicate',resolution_note='A current pathology result already uses this provider result reference.',updated_at=now()
      where id=v_row.id;
      update public.operations_work_item
      set status='cancelled',updated_at=now()
      where practice_id=v_row.practice_id and source_entity_type='pathology_result_inbox' and source_entity_id=v_row.id
        and category='pathology' and status in ('open','in_progress','waiting','blocked');
      return jsonb_build_object('status','duplicate','existing_result_id',v_duplicate,'inbox_id',v_row.id);
    end if;
  end if;

  v_order:=v_row.matched_order_id;
  if v_order is null then
    insert into public.pathology_order(
      practice_id,patient_id,provider_id,order_number,status,delivery_mode,transport_status,priority,
      order_category,external_order_ref,treating_practitioner_user_id,created_by,ordered_at,submitted_at
    ) values(
      v_row.practice_id,v_row.patient_id,v_row.provider_id,
      'EXT-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
      'in_progress',case when v_row.source_mode='electronic' then 'electronic' else 'manual' end,
      case when v_row.source_mode='electronic' then 'accepted' else 'manual' end,
      case v_row.overall_flag_hint when 'critical' then 'stat' when 'abnormal' then 'urgent' else 'routine' end,
      'other',v_row.external_order_ref,
      case when exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_row.practice_id and m.role='practitioner' and m.active) then v_user else null end,
      v_user,now(),now()
    ) returning id into v_order;

    update public.pathology_result_inbox set matched_order_id=v_order,status='order_matched',updated_at=now() where id=v_row.id;
  end if;

  select public.record_pathology_result(
    v_order,p_status,'unknown',v_row.external_result_ref,v_row.accession_number,null,p_reported_at,
    coalesce(nullif(trim(coalesce(p_report_comment,'')),''),v_row.summary),p_items
  ) into v_result;

  update public.pathology_result
  set source_mode=case when v_row.source_mode='electronic' then 'electronic' else 'manual' end,
      payload_sha256=v_row.payload_sha256,
      updated_at=now()
  where id=v_result;

  update public.pathology_result_inbox
  set status='filed',matched_order_id=v_order,resolution_note='Filed into the clinical record after clinician-confirmed matching.',updated_at=now()
  where id=v_row.id;

  update public.operations_work_item
  set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
  where practice_id=v_row.practice_id and source_entity_type='pathology_result_inbox' and source_entity_id=v_row.id
    and category='pathology' and status in ('open','in_progress','waiting','blocked');

  return jsonb_build_object('status','filed','inbox_id',v_row.id,'order_id',v_order,'result_id',v_result);
end $function$
;
revoke all on function public.file_pathology_result_inbox(uuid,text,timestamp with time zone,text,jsonb) from public, anon;
grant execute on function public.file_pathology_result_inbox(uuid,text,timestamp with time zone,text,jsonb) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_pathology_ai_readiness(p_practice_id uuid)
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
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')
  ) then raise exception 'Clinical access role required'; end if;

  select * into v_policy
  from public.practice_assist_policy
  where practice_id=p_practice_id and capability_key='pathology.result_intelligence';

  if not found or not v_policy.enabled then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','PATHOLOGY_AI_POLICY_DISABLED',
      'message','Pathology AI result intelligence has not been enabled for this practice.'
    ));
    return jsonb_build_object(
      'ready',false,'policy_enabled',false,'provider_ready',false,
      'human_review_required',true,'raw_input_retained',false,'raw_output_retained',false,
      'blockers',v_blockers
    );
  end if;

  if v_policy.allowed_data_class<>'health_special' or v_policy.retain_raw_input or v_policy.retain_raw_output
     or not v_policy.require_aal2 or not v_policy.human_review_required then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','PATHOLOGY_AI_POLICY_UNSAFE',
      'message','Practice AI policy does not meet the required pathology safety profile.'
    ));
  end if;

  if v_policy.provider_config_id is null then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','PATHOLOGY_AI_PROVIDER_MISSING','message','No approved AI provider is selected.'
    ));
  else
    select * into v_provider from public.assist_provider_config where id=v_policy.provider_config_id;
    if not found or v_provider.review_status<>'approved' or not v_provider.transport_ready
       or not v_provider.phi_approved or v_provider.maximum_approved_data_class<>'health_special' then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','PATHOLOGY_AI_PROVIDER_NOT_READY',
        'message','Selected AI provider is not approved, transport-ready and authorised for health-special information.'
      ));
    end if;
  end if;

  return jsonb_build_object(
    'ready',jsonb_array_length(v_blockers)=0,
    'policy_enabled',v_policy.enabled,
    'provider_ready',jsonb_array_length(v_blockers)=0,
    'provider_config_id',v_policy.provider_config_id,
    'model_id',case when v_provider.id is null then null else v_provider.model_id end,
    'human_review_required',true,
    'raw_input_retained',false,
    'raw_output_retained',false,
    'blockers',v_blockers
  );
end $function$
;
revoke all on function public.get_pathology_ai_readiness(uuid) from public, anon;
grant execute on function public.get_pathology_ai_readiness(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_pathology_inbox_match_candidates(p_inbox_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_row public.pathology_result_inbox%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_row from public.pathology_result_inbox where id=p_inbox_id;
  if not found then raise exception 'Pathology inbox result not found'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_row.practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;

  return jsonb_build_object(
    'inbox_id',v_row.id,
    'order_candidates',coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_id',o.id,'patient_id',o.patient_id,'order_number',o.order_number,'external_order_ref',o.external_order_ref,
        'status',o.status,'score',
          case when v_row.external_order_ref is not null and o.external_order_ref=v_row.external_order_ref then 100
               when v_row.patient_id is not null and o.patient_id=v_row.patient_id then 70 else 40 end,
        'basis',
          case when v_row.external_order_ref is not null and o.external_order_ref=v_row.external_order_ref then 'exact_external_order_ref'
               when v_row.patient_id is not null and o.patient_id=v_row.patient_id then 'confirmed_patient_recent_order'
               else 'same_provider_recent_order' end
      ) order by
        case when v_row.external_order_ref is not null and o.external_order_ref=v_row.external_order_ref then 0
             when v_row.patient_id is not null and o.patient_id=v_row.patient_id then 1 else 2 end,
        o.created_at desc)
      from (
        select o.*
        from public.pathology_order o
        where o.practice_id=v_row.practice_id and o.provider_id=v_row.provider_id
          and o.created_at>=now()-interval '90 days'
          and (
            (v_row.external_order_ref is not null and o.external_order_ref=v_row.external_order_ref)
            or (v_row.patient_id is not null and o.patient_id=v_row.patient_id)
          )
        order by o.created_at desc
        limit 10
      ) o
    ),'[]'::jsonb),
    'patient_candidates',coalesce((
      select jsonb_agg(jsonb_build_object(
        'patient_id',p.id,'display_name',p.display_name,'date_of_birth',p.date_of_birth,
        'score',case when v_row.patient_id=p.id then 100
                     when v_row.external_patient_ref is not null and p.source_patient_ref=v_row.external_patient_ref then 85 else 50 end,
        'basis',case when v_row.patient_id=p.id then 'already_confirmed'
                     when v_row.external_patient_ref is not null and p.source_patient_ref=v_row.external_patient_ref then 'external_patient_reference'
                     else 'manual_review' end
      ) order by case when v_row.patient_id=p.id then 0 else 1 end,p.display_name)
      from public.crm_patient p
      where p.practice_id=v_row.practice_id and p.status='active'
        and (
          p.id=v_row.patient_id
          or (v_row.external_patient_ref is not null and p.source_patient_ref=v_row.external_patient_ref)
        )
      limit 10
    ),'[]'::jsonb)
  );
end $function$
;
revoke all on function public.get_pathology_inbox_match_candidates(uuid) from public, anon;
grant execute on function public.get_pathology_inbox_match_candidates(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_pathology_metrics(p_practice_id uuid, p_window_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_start timestamptz:=now()-make_interval(days=>greatest(1,least(coalesce(p_window_days,30),365)));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;
  return jsonb_build_object(
    'orders_created',(select count(*) from public.pathology_order o where o.practice_id=p_practice_id and o.created_at>=v_start),
    'orders_open',(select count(*) from public.pathology_order o where o.practice_id=p_practice_id and o.status in ('draft','ordered','submitted','acknowledged','collected','in_progress','partial')),
    'results_received',(select count(*) from public.pathology_result r where r.practice_id=p_practice_id and r.received_at>=v_start and r.is_current),
    'abnormal_results',(select count(*) from public.pathology_result r where r.practice_id=p_practice_id and r.received_at>=v_start and r.is_current and r.overall_flag='abnormal'),
    'critical_results',(select count(*) from public.pathology_result r where r.practice_id=p_practice_id and r.received_at>=v_start and r.is_current and r.overall_flag='critical'),
    'corrected_results',(select count(*) from public.pathology_result r where r.practice_id=p_practice_id and r.received_at>=v_start and r.status='corrected'),
    'unacknowledged_final',(select count(*) from public.pathology_result r where r.practice_id=p_practice_id and r.is_current and r.status in ('final','corrected') and not exists(select 1 from public.pathology_result_acknowledgement a where a.result_id=r.id)),
    'unacknowledged_critical',(select count(*) from public.pathology_result r where r.practice_id=p_practice_id and r.is_current and r.status in ('final','corrected') and r.overall_flag='critical' and not exists(select 1 from public.pathology_result_acknowledgement a where a.result_id=r.id)),
    'overdue_safety_cases',(select count(*) from public.pathology_safety_case c where c.practice_id=p_practice_id and c.status='open' and c.sla_due_at<now()),
    'escalated_safety_cases',(select count(*) from public.pathology_safety_case c where c.practice_id=p_practice_id and c.status='open' and c.escalation_level>0),
    'unmatched_inbox',(select count(*) from public.pathology_result_inbox i where i.practice_id=p_practice_id and i.status in ('unmatched','patient_matched','order_matched','quarantined')),
    'critical_inbox',(select count(*) from public.pathology_result_inbox i where i.practice_id=p_practice_id and i.status in ('unmatched','patient_matched','order_matched','quarantined') and i.overall_flag_hint='critical'),
    'open_follow_up',(select count(*) from public.pathology_follow_up_action f where f.practice_id=p_practice_id and f.status in ('planned','in_progress')),
    'overdue_follow_up',(select count(*) from public.pathology_follow_up_action f where f.practice_id=p_practice_id and f.status in ('planned','in_progress') and f.due_at<now()),
    'held_patient_release',(select count(*) from public.pathology_result_release r where r.practice_id=p_practice_id and r.status='held'),
    'approved_patient_release',(select count(*) from public.pathology_result_release r where r.practice_id=p_practice_id and r.status='approved'),
    'specimens_rejected',(select count(*) from public.pathology_specimen s where s.practice_id=p_practice_id and s.status='rejected' and s.updated_at>=v_start),
    'trend_series_available',(
      select count(*) from (
        select ri.concept_id,coalesce(c.canonical_key,lower(coalesce(nullif(trim(ri.test_code),''),trim(ri.test_name)))) k
        from public.pathology_result_item ri
        join public.pathology_result r on r.id=ri.result_id
        left join public.pathology_test_concept c on c.id=ri.concept_id
        where ri.practice_id=p_practice_id and ri.value_type='numeric' and r.is_current and r.status in ('final','corrected')
        group by ri.concept_id,coalesce(c.canonical_key,lower(coalesce(nullif(trim(ri.test_code),''),trim(ri.test_name))))
        having count(*)>=2
      ) s
    )
  );
end $function$
;
revoke all on function public.get_pathology_metrics(uuid,integer) from public, anon;
grant execute on function public.get_pathology_metrics(uuid,integer) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_pathology_numeric_trend(p_practice_id uuid, p_patient_id uuid, p_test_key text, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_key text:=lower(trim(coalesce(p_test_key,'')));
  v_limit integer:=greatest(2,least(coalesce(p_limit,20),100));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(v_key)<1 then raise exception 'Test key is required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then
    raise exception 'Patient is not in this practice';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'result_id',x.result_id,'test_code',x.test_code,'test_name',x.test_name,'value',x.value_numeric,
      'unit',x.unit,'reference_range',x.reference_range,'flag',x.flag,'observed_at',x.observed_at,
      'provider_name',x.provider_name
    ) order by x.observed_at)
    from (
      select ri.result_id,ri.test_code,ri.test_name,ri.value_numeric,ri.unit,ri.reference_range,ri.flag,
             coalesce(ri.observation_at,r.reported_at,r.received_at) observed_at,p.name provider_name
      from public.pathology_result_item ri
      join public.pathology_result r on r.id=ri.result_id
      join public.integration_provider p on p.id=r.provider_id
      where ri.practice_id=p_practice_id and r.patient_id=p_patient_id and ri.value_type='numeric'
        and lower(coalesce(nullif(trim(ri.test_code),''),trim(ri.test_name)))=v_key
        and r.status in ('final','corrected')
      order by coalesce(ri.observation_at,r.reported_at,r.received_at) desc
      limit v_limit
    ) x
  ),'[]'::jsonb);
end $function$
;
revoke all on function public.get_pathology_numeric_trend(uuid,uuid,text,integer) from public, anon;
grant execute on function public.get_pathology_numeric_trend(uuid,uuid,text,integer) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_pathology_readiness(p_practice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'storage', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_registered int; v_external int; v_sandbox_order_cap int; v_sandbox_conn int;
  v_prod_caps int; v_prod_conn int; v_open_requirements int; v_unacked int; v_critical int;
  v_bucket_private boolean; v_release_policy boolean; v_safety_cron boolean; v_intelligence boolean;
  v_blockers jsonb:='[]'::jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;

  select count(*) into v_registered from public.integration_provider where provider_type='pathology_lab' and lifecycle_status<>'retired';
  select count(*) into v_external from public.integration_provider where provider_type='pathology_lab' and slug<>'practicectrl-pathology-sandbox' and lifecycle_status<>'retired';

  select count(*) into v_sandbox_order_cap
  from public.integration_adapter_capability ac join public.integration_provider p on p.id=ac.provider_id
  where p.slug='practicectrl-pathology-sandbox' and ac.capability_code='pathology_order_submit' and ac.executable_sandbox;

  select count(*) into v_sandbox_conn
  from public.practice_integration_connection c join public.integration_provider p on p.id=c.provider_id
  where c.practice_id=p_practice_id and c.environment='sandbox' and c.status in ('sandbox_active','active') and p.slug='practicectrl-pathology-sandbox';

  select count(*) into v_prod_caps
  from public.integration_adapter_capability ac join public.integration_provider p on p.id=ac.provider_id
  where p.provider_type='pathology_lab' and p.slug<>'practicectrl-pathology-sandbox'
    and ac.capability_code in ('pathology_order_submit','pathology_result_receive') and ac.executable_production;

  select count(*) into v_prod_conn
  from public.practice_integration_connection c join public.integration_provider p on p.id=c.provider_id
  where c.practice_id=p_practice_id and c.environment='production' and c.status in ('production_ready','active')
    and p.provider_type='pathology_lab' and p.slug<>'practicectrl-pathology-sandbox';

  select count(*) into v_open_requirements
  from public.integration_requirement r join public.integration_provider p on p.id=r.provider_id
  where p.provider_type='pathology_lab' and p.slug<>'practicectrl-pathology-sandbox'
    and r.status in ('open','in_progress','waiting_external','blocked');

  select exists(select 1 from storage.buckets where id='pathology-result-files' and public=false) into v_bucket_private;
  select exists(select 1 from public.pathology_release_policy where practice_id=p_practice_id) into v_release_policy;
  select exists(select 1 from cron.job where jobname='practicectrl-pathology-safety-10m' and active and command='select private.process_pathology_safety_escalations();') into v_safety_cron;
  v_intelligence:=to_regclass('public.pathology_result_inbox') is not null
    and to_regclass('public.pathology_safety_case') is not null
    and to_regclass('public.pathology_follow_up_action') is not null
    and to_regprocedure('public.get_pathology_trend_series(uuid,uuid,uuid,text,integer)') is not null;

  select count(*) into v_unacked from public.pathology_result r
  where r.practice_id=p_practice_id and r.is_current and r.status in ('final','corrected')
    and not exists(select 1 from public.pathology_result_acknowledgement a where a.result_id=r.id);
  select count(*) into v_critical from public.pathology_result r
  where r.practice_id=p_practice_id and r.is_current and r.status in ('final','corrected') and r.overall_flag='critical'
    and not exists(select 1 from public.pathology_result_acknowledgement a where a.result_id=r.id);

  if not v_bucket_private then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PATHOLOGY_STORAGE_NOT_PRIVATE','scope','staging','message','Pathology report storage is not private.')); end if;
  if v_sandbox_order_cap=0 or v_sandbox_conn=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PATHOLOGY_SANDBOX_ORDER_NOT_READY','scope','staging','message','Synthetic pathology order submission is not executable for this practice.')); end if;
  if not v_release_policy then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PATHOLOGY_RELEASE_POLICY_MISSING','scope','staging','message','Patient result-release policy is not configured.')); end if;
  if not v_safety_cron then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PATHOLOGY_SAFETY_ESCALATION_INACTIVE','scope','staging','message','Critical-result escalation scheduler is not active.')); end if;
  if not v_intelligence then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PATHOLOGY_INTELLIGENCE_INCOMPLETE','scope','staging','message','Pathology inbox, trends or closed-loop safety components are incomplete.')); end if;
  if v_prod_caps<2 or v_prod_conn=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PATHOLOGY_PRODUCTION_TRANSPORT_NOT_READY','scope','production','message','No external laboratory has executable production order/result capabilities and a production practice connection.')); end if;
  if v_open_requirements>0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PATHOLOGY_PROVIDER_ONBOARDING_OPEN','scope','production','message',v_open_requirements||' pathology provider onboarding requirements remain open.')); end if;

  return jsonb_build_object(
    'generated_at',now(),'practice_id',p_practice_id,
    'registered_pathology_providers',v_registered,'external_providers_researched',v_external,
    'private_report_storage',v_bucket_private,'release_policy_ready',v_release_policy,
    'safety_escalation_ready',v_safety_cron,'intelligence_layer_ready',v_intelligence,
    'sandbox_order_submission_ready',v_sandbox_order_cap>0 and v_sandbox_conn>0,
    'production_transport_ready',v_prod_caps>=2 and v_prod_conn>0,
    'production_capability_count',v_prod_caps,'production_connection_count',v_prod_conn,
    'open_provider_requirements',v_open_requirements,
    'unacknowledged_final_results',v_unacked,'unacknowledged_critical_results',v_critical,
    'blockers',v_blockers
  );
end $function$
;
revoke all on function public.get_pathology_readiness(uuid) from public, anon;
grant execute on function public.get_pathology_readiness(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_pathology_trend_catalog(p_practice_id uuid, p_patient_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid());
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'concept_id',concept_id,'test_key',test_key,'display_name',display_name,'loinc_code',loinc_code,
      'point_count',point_count,'latest_value',latest_value,'latest_unit',latest_unit,'latest_at',latest_at
    ) order by latest_at desc)
    from (
      select ri.concept_id,
             coalesce(c.canonical_key,lower(coalesce(nullif(trim(ri.test_code),''),trim(ri.test_name)))) test_key,
             coalesce(c.display_name,max(ri.test_name)) display_name,
             c.loinc_code,
             count(*) point_count,
             (array_agg(ri.value_numeric order by coalesce(ri.observation_at,r.reported_at,r.received_at) desc))[1] latest_value,
             (array_agg(ri.unit order by coalesce(ri.observation_at,r.reported_at,r.received_at) desc))[1] latest_unit,
             max(coalesce(ri.observation_at,r.reported_at,r.received_at)) latest_at
      from public.pathology_result_item ri
      join public.pathology_result r on r.id=ri.result_id
      left join public.pathology_test_concept c on c.id=ri.concept_id
      where ri.practice_id=p_practice_id and r.patient_id=p_patient_id and ri.value_type='numeric'
        and r.status in ('final','corrected') and r.is_current
      group by ri.concept_id,c.canonical_key,c.display_name,c.loinc_code,
               coalesce(c.canonical_key,lower(coalesce(nullif(trim(ri.test_code),''),trim(ri.test_name))))
      having count(*)>=2
    ) x
  ),'[]'::jsonb);
end $function$
;
revoke all on function public.get_pathology_trend_catalog(uuid,uuid) from public, anon;
grant execute on function public.get_pathology_trend_catalog(uuid,uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_pathology_trend_series(p_practice_id uuid, p_patient_id uuid, p_concept_id uuid DEFAULT NULL::uuid, p_test_key text DEFAULT NULL::text, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_limit integer:=greatest(2,least(coalesce(p_limit,30),200));
  v_key text:=lower(trim(coalesce(p_test_key,'')));
  v_points jsonb;
  v_count int;
  v_first numeric;
  v_last numeric;
  v_name text;
  v_loinc text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_concept_id is null and length(v_key)<1 then raise exception 'Concept or test key is required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')) then
    raise exception 'Clinical access role required';
  end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then raise exception 'Patient is not in this practice'; end if;

  if p_concept_id is not null then
    select display_name,loinc_code into v_name,v_loinc from public.pathology_test_concept where id=p_concept_id;
  end if;

  with series as (
    select ri.result_id,ri.concept_id,ri.test_code,ri.test_name,ri.value_numeric,ri.unit,ri.reference_range,ri.flag,
           coalesce(ri.observation_at,r.reported_at,r.received_at) observed_at,p.name provider_name,r.version_no
    from public.pathology_result_item ri
    join public.pathology_result r on r.id=ri.result_id
    join public.integration_provider p on p.id=r.provider_id
    where ri.practice_id=p_practice_id and r.patient_id=p_patient_id and ri.value_type='numeric'
      and r.status in ('final','corrected') and r.is_current
      and (
        (p_concept_id is not null and ri.concept_id=p_concept_id)
        or (
          p_concept_id is null and (
            lower(coalesce(nullif(trim(ri.test_code),''),trim(ri.test_name)))=v_key
            or lower(trim(ri.test_name))=v_key
          )
        )
      )
    order by coalesce(ri.observation_at,r.reported_at,r.received_at) desc
    limit v_limit
  ),
  ordered as (
    select * from series order by observed_at
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'result_id',result_id,'concept_id',concept_id,'test_code',test_code,'test_name',test_name,'value',value_numeric,
      'unit',unit,'reference_range',reference_range,'flag',flag,'observed_at',observed_at,'provider_name',provider_name,'version_no',version_no
    ) order by observed_at),'[]'::jsonb),
    count(*),
    (array_agg(value_numeric order by observed_at))[1],
    (array_agg(value_numeric order by observed_at desc))[1],
    coalesce(v_name,(array_agg(test_name order by observed_at desc))[1])
  into v_points,v_count,v_first,v_last,v_name
  from ordered;

  return jsonb_build_object(
    'concept_id',p_concept_id,'display_name',v_name,'loinc_code',v_loinc,'point_count',v_count,
    'first_value',v_first,'latest_value',v_last,
    'absolute_change',case when v_count>=2 then v_last-v_first else null end,
    'percent_change',case when v_count>=2 and v_first<>0 then round(((v_last-v_first)/abs(v_first))*100,2) else null end,
    'series',v_points,
    'interpretation',null
  );
end $function$
;
revoke all on function public.get_pathology_trend_series(uuid,uuid,uuid,text,integer) from public, anon;
grant execute on function public.get_pathology_trend_series(uuid,uuid,uuid,text,integer) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.match_pathology_result_inbox(p_inbox_id uuid, p_patient_id uuid, p_order_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_row public.pathology_result_inbox%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_row from public.pathology_result_inbox where id=p_inbox_id for update;
  if not found then raise exception 'Pathology inbox result not found'; end if;
  if v_row.status in ('filed','duplicate','rejected') then raise exception 'Resolved pathology inbox result cannot be rematched'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_row.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=v_row.practice_id) then
    raise exception 'Patient is not in this practice';
  end if;
  if p_order_id is not null and not exists(select 1 from public.pathology_order o where o.id=p_order_id and o.practice_id=v_row.practice_id and o.patient_id=p_patient_id and o.provider_id=v_row.provider_id) then
    raise exception 'Selected pathology order does not match practice, patient and provider';
  end if;

  update public.pathology_result_inbox
  set patient_id=p_patient_id,matched_order_id=p_order_id,
      status=case when p_order_id is null then 'patient_matched' else 'order_matched' end,
      match_confidence=100,match_basis='clinician_confirmed',
      matched_by=v_user,matched_at=now(),updated_at=now()
  where id=p_inbox_id;

  update public.operations_work_item
  set patient_id=p_patient_id,updated_at=now()
  where practice_id=v_row.practice_id and source_entity_type='pathology_result_inbox' and source_entity_id=p_inbox_id;

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(v_row.practice_id,p_patient_id,'result',p_inbox_id,'unsolicited_result_matched',v_user,jsonb_build_object('order_id',p_order_id,'basis','clinician_confirmed'));

  return jsonb_build_object('inbox_id',p_inbox_id,'patient_id',p_patient_id,'order_id',p_order_id,
    'status',case when p_order_id is null then 'patient_matched' else 'order_matched' end,'match_confidence',100);
end $function$
;
revoke all on function public.match_pathology_result_inbox(uuid,uuid,uuid) from public, anon;
grant execute on function public.match_pathology_result_inbox(uuid,uuid,uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_assign_order_item_concept()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_provider uuid;
begin
  if new.concept_id is null then
    select provider_id into v_provider from public.pathology_order where id=new.order_id;
    new.concept_id:=private.resolve_pathology_concept(v_provider,new.test_code,new.test_name);
  end if;
  return new;
end $function$
;
revoke all on function public.pathology_assign_order_item_concept() from public, anon;
grant execute on function public.pathology_assign_order_item_concept() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_assign_result_item_concept()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_provider uuid;
begin
  if new.concept_id is null then
    select provider_id into v_provider from public.pathology_result where id=new.result_id;
    new.concept_id:=private.resolve_pathology_concept(v_provider,new.test_code,new.test_name);
  end if;
  return new;
end $function$
;
revoke all on function public.pathology_assign_result_item_concept() from public, anon;
grant execute on function public.pathology_assign_result_item_concept() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_enforce_ack_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists(select 1 from public.pathology_result r where r.id=new.result_id and r.practice_id=new.practice_id) then
    raise exception 'Pathology acknowledgement tenant mismatch';
  end if;
  return new;
end $function$
;
revoke all on function public.pathology_enforce_ack_consistency() from public, anon;
grant execute on function public.pathology_enforce_ack_consistency() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_enforce_document_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists(select 1 from public.pathology_result r where r.id=new.result_id and r.practice_id=new.practice_id) then
    raise exception 'Pathology result document tenant mismatch';
  end if;
  if new.storage_path not like new.practice_id::text||'/%' then
    raise exception 'Pathology document storage path must begin with the practice id';
  end if;
  return new;
end $function$
;
revoke all on function public.pathology_enforce_document_consistency() from public, anon;
grant execute on function public.pathology_enforce_document_consistency() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_enforce_order_item_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists(select 1 from public.pathology_order o where o.id=new.order_id and o.practice_id=new.practice_id) then
    raise exception 'Pathology order item tenant mismatch';
  end if;
  return new;
end $function$
;
revoke all on function public.pathology_enforce_order_item_consistency() from public, anon;
grant execute on function public.pathology_enforce_order_item_consistency() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_enforce_result_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_order public.pathology_order%rowtype;
begin
  select * into v_order from public.pathology_order where id=new.order_id;
  if not found then raise exception 'Pathology order not found'; end if;
  if v_order.practice_id<>new.practice_id or v_order.patient_id<>new.patient_id or v_order.provider_id<>new.provider_id then
    raise exception 'Pathology result does not match the order tenant/patient/provider';
  end if;
  if new.encounter_id is not null and (v_order.encounter_id is distinct from new.encounter_id) then
    raise exception 'Pathology result encounter does not match the order';
  end if;
  return new;
end $function$
;
revoke all on function public.pathology_enforce_result_consistency() from public, anon;
grant execute on function public.pathology_enforce_result_consistency() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_enforce_result_item_consistency()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_order uuid;
begin
  select r.order_id into v_order from public.pathology_result r where r.id=new.result_id and r.practice_id=new.practice_id;
  if v_order is null then raise exception 'Pathology result item tenant mismatch'; end if;
  if new.order_item_id is not null and not exists(
    select 1 from public.pathology_order_item oi
    where oi.id=new.order_item_id and oi.order_id=v_order and oi.practice_id=new.practice_id
  ) then raise exception 'Pathology result item does not match the pathology order'; end if;
  return new;
end $function$
;
revoke all on function public.pathology_enforce_result_item_consistency() from public, anon;
grant execute on function public.pathology_enforce_result_item_consistency() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_recompute_overall_flag()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_result uuid:=coalesce(new.result_id,old.result_id); v_flag text;
begin
  select case
    when count(*) filter(where flag='critical')>0 then 'critical'
    when count(*) filter(where flag in ('high','low','abnormal'))>0 then 'abnormal'
    when count(*)>0 and count(*) filter(where flag='normal')=count(*) then 'normal'
    else 'unknown'
  end into v_flag
  from public.pathology_result_item where result_id=v_result;

  update public.pathology_result set overall_flag=v_flag,updated_at=now()
  where id=v_result and overall_flag is distinct from v_flag;
  return coalesce(new,old);
end $function$
;
revoke all on function public.pathology_recompute_overall_flag() from public, anon;
grant execute on function public.pathology_recompute_overall_flag() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.pathology_result_revision_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_prior public.pathology_result%rowtype;
begin
  if new.version_no=1 and new.correction_of_result_id is not null then
    raise exception 'Version 1 pathology results cannot reference a prior correction';
  end if;
  if new.version_no>1 then
    if new.correction_of_result_id is null then raise exception 'Corrected pathology result requires the prior result'; end if;
    select * into v_prior from public.pathology_result where id=new.correction_of_result_id;
    if not found then raise exception 'Prior pathology result not found'; end if;
    if v_prior.practice_id<>new.practice_id or v_prior.patient_id<>new.patient_id or v_prior.order_id<>new.order_id or v_prior.provider_id<>new.provider_id then
      raise exception 'Corrected pathology result must remain in the same practice, patient, order and provider chain';
    end if;
    if new.version_no<>v_prior.version_no+1 then raise exception 'Pathology result versions must increment by one'; end if;
    if new.status<>'corrected' then raise exception 'Result revisions after version 1 must use corrected status'; end if;
  end if;
  return new;
end $function$
;
revoke all on function public.pathology_result_revision_guard() from public, anon;
grant execute on function public.pathology_result_revision_guard() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.record_corrected_pathology_result(p_prior_result_id uuid, p_external_result_ref text, p_accession_number text, p_reported_at timestamp with time zone, p_report_comment text, p_correction_reason text, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_prior public.pathology_result%rowtype;
  v_id uuid;
  v_item jsonb;
  v_type text;
  v_name text;
  v_numeric numeric;
  v_text text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>200 then
    raise exception 'Provide between 1 and 200 corrected pathology result items';
  end if;

  select * into v_prior from public.pathology_result where id=p_prior_result_id for update;
  if not found then raise exception 'Prior pathology result not found'; end if;
  if not v_prior.is_current or v_prior.status not in ('final','corrected') then
    raise exception 'Only the current final/corrected pathology result can be corrected';
  end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_prior.practice_id and m.active and m.role in ('practitioner','clinical_admin')
  ) then raise exception 'Clinical write role required'; end if;

  update public.pathology_result
  set is_current=false,superseded_at=now(),updated_at=now()
  where id=v_prior.id;

  update public.pathology_result_release
  set status=case when status='released' then 'revoked' else status end,
      hold_reason='Superseded by a corrected pathology result.',
      revoked_by=case when status='released' then v_user else revoked_by end,
      revoked_at=case when status='released' then now() else revoked_at end,
      updated_at=now()
  where result_id=v_prior.id;

  update public.pathology_safety_case
  set status='cancelled',resolved_at=coalesce(resolved_at,now()),updated_at=now()
  where result_id=v_prior.id and status in ('open','acknowledged');

  update public.operations_work_item
  set status='cancelled',updated_at=now()
  where practice_id=v_prior.practice_id and source_entity_type='pathology_result' and source_entity_id=v_prior.id
    and category='pathology' and status in ('open','in_progress','waiting','blocked');

  insert into public.pathology_result(
    practice_id,order_id,patient_id,encounter_id,provider_id,status,overall_flag,
    external_result_ref,accession_number,specimen_collected_at,reported_at,source_mode,
    report_comment,created_by,version_no,correction_of_result_id,correction_reason,is_current
  ) values(
    v_prior.practice_id,v_prior.order_id,v_prior.patient_id,v_prior.encounter_id,v_prior.provider_id,
    'corrected','unknown',
    coalesce(nullif(trim(coalesce(p_external_result_ref,'')),''),v_prior.external_result_ref),
    coalesce(nullif(trim(coalesce(p_accession_number,'')),''),v_prior.accession_number),
    v_prior.specimen_collected_at,coalesce(p_reported_at,now()),v_prior.source_mode,
    nullif(trim(coalesce(p_report_comment,'')),''),v_user,
    v_prior.version_no+1,v_prior.id,nullif(trim(coalesce(p_correction_reason,'')),''),true
  ) returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_name:=trim(coalesce(v_item->>'test_name',''));
    if length(v_name)<2 then raise exception 'Every corrected result item requires a test name'; end if;
    v_type:=coalesce(nullif(v_item->>'value_type',''),'text');
    if v_type not in ('numeric','text','qualitative') then raise exception 'Invalid pathology result value type'; end if;
    v_numeric:=case when v_type='numeric' and nullif(v_item->>'value_numeric','') is not null then (v_item->>'value_numeric')::numeric else null end;
    v_text:=case when v_type in ('text','qualitative') then nullif(trim(coalesce(v_item->>'value_text','')),'') else null end;
    if v_type='numeric' and v_numeric is null then raise exception 'Numeric result requires a numeric value'; end if;
    if v_type in ('text','qualitative') and v_text is null then raise exception 'Text/qualitative result requires a value'; end if;

    insert into public.pathology_result_item(
      practice_id,result_id,order_item_id,concept_id,test_code,test_name,value_type,value_numeric,value_text,unit,
      reference_range,flag,observation_at,comment
    ) values(
      v_prior.practice_id,v_id,
      case when nullif(v_item->>'order_item_id','') is null then null else (v_item->>'order_item_id')::uuid end,
      case when nullif(v_item->>'concept_id','') is null then null else (v_item->>'concept_id')::uuid end,
      nullif(trim(coalesce(v_item->>'test_code','')),''),v_name,v_type,v_numeric,v_text,
      nullif(trim(coalesce(v_item->>'unit','')),''),
      nullif(trim(coalesce(v_item->>'reference_range','')),''),
      coalesce(nullif(v_item->>'flag',''),'unknown'),
      case when nullif(v_item->>'observation_at','') is null then null else (v_item->>'observation_at')::timestamptz end,
      nullif(trim(coalesce(v_item->>'comment','')),'')
    );
  end loop;

  update public.pathology_result
  set superseded_by_result_id=v_id,updated_at=now()
  where id=v_prior.id;

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(v_prior.practice_id,v_prior.patient_id,'result',v_id,'corrected_result_recorded',v_user,
    jsonb_build_object('correction_of_result_id',v_prior.id,'version_no',v_prior.version_no+1,'correction_reason',p_correction_reason));

  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(v_prior.practice_id,v_prior.patient_id,'pathology_result',coalesce(p_reported_at,now()),
    'Corrected pathology result available',
    'Version '||(v_prior.version_no+1)::text||' supersedes the previous pathology result.',
    'pathology_result',v_id,v_user,'PracticeCtrl',
    jsonb_build_object('superseded_result_id',v_prior.id,'version_no',v_prior.version_no+1));

  return v_id;
end $function$
;
revoke all on function public.record_corrected_pathology_result(uuid,text,text,timestamp with time zone,text,text,jsonb) from public, anon;
grant execute on function public.record_corrected_pathology_result(uuid,text,text,timestamp with time zone,text,text,jsonb) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.record_pathology_result(p_order_id uuid, p_status text, p_overall_flag text, p_external_result_ref text, p_accession_number text, p_specimen_collected_at timestamp with time zone, p_reported_at timestamp with time zone, p_report_comment text, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_order public.pathology_order%rowtype;
  v_id uuid;
  v_item jsonb;
  v_type text;
  v_name text;
  v_numeric numeric;
  v_text text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_status not in ('preliminary','final','corrected') then raise exception 'Invalid result status'; end if;
  if p_overall_flag not in ('normal','abnormal','critical','unknown') then raise exception 'Invalid overall result flag'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>200 then
    raise exception 'Provide between 1 and 200 pathology result items';
  end if;

  select * into v_order from public.pathology_order where id=p_order_id;
  if not found then raise exception 'Pathology order not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_order.practice_id and m.active and m.role in ('practitioner','clinical_admin')
  ) then raise exception 'Clinical write role required'; end if;

  insert into public.pathology_result(
    practice_id,order_id,patient_id,encounter_id,provider_id,status,overall_flag,
    external_result_ref,accession_number,specimen_collected_at,reported_at,source_mode,
    report_comment,created_by
  ) values(
    v_order.practice_id,v_order.id,v_order.patient_id,v_order.encounter_id,v_order.provider_id,p_status,p_overall_flag,
    nullif(trim(coalesce(p_external_result_ref,'')),''),nullif(trim(coalesce(p_accession_number,'')),''),
    p_specimen_collected_at,coalesce(p_reported_at,now()),'manual',
    nullif(trim(coalesce(p_report_comment,'')),''),v_user
  ) returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_name:=trim(coalesce(v_item->>'test_name',''));
    if length(v_name)<2 then raise exception 'Every result item requires a test name'; end if;
    v_type:=coalesce(nullif(v_item->>'value_type',''),'text');
    if v_type not in ('numeric','text','qualitative') then raise exception 'Invalid pathology result value type'; end if;
    v_numeric:=case when v_type='numeric' and nullif(v_item->>'value_numeric','') is not null then (v_item->>'value_numeric')::numeric else null end;
    v_text:=case when v_type in ('text','qualitative') then nullif(trim(coalesce(v_item->>'value_text','')),'') else null end;
    if v_type='numeric' and v_numeric is null then raise exception 'Numeric result requires a numeric value'; end if;
    if v_type in ('text','qualitative') and v_text is null then raise exception 'Text/qualitative result requires a value'; end if;

    insert into public.pathology_result_item(
      practice_id,result_id,order_item_id,test_code,test_name,value_type,value_numeric,value_text,unit,
      reference_range,flag,observation_at,comment
    ) values(
      v_order.practice_id,v_id,
      case when nullif(v_item->>'order_item_id','') is null then null else (v_item->>'order_item_id')::uuid end,
      nullif(trim(coalesce(v_item->>'test_code','')),''),v_name,v_type,v_numeric,v_text,
      nullif(trim(coalesce(v_item->>'unit','')),''),
      nullif(trim(coalesce(v_item->>'reference_range','')),''),
      coalesce(nullif(v_item->>'flag',''),'unknown'),
      case when nullif(v_item->>'observation_at','') is null then null else (v_item->>'observation_at')::timestamptz end,
      nullif(trim(coalesce(v_item->>'comment','')),'')
    );
  end loop;

  update public.pathology_order
  set status=case when p_status in ('final','corrected') then 'completed' else 'partial' end,
      completed_at=case when p_status in ('final','corrected') then now() else completed_at end,
      updated_at=now()
  where id=v_order.id;

  if p_status in ('final','corrected') then
    update public.pathology_order_item set status='resulted' where order_id=v_order.id and status<>'cancelled';
  end if;

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(v_order.practice_id,v_order.patient_id,'result',v_id,'manual_result_recorded',v_user,jsonb_build_object('status',p_status,'overall_flag',p_overall_flag,'item_count',jsonb_array_length(p_items)));

  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(v_order.practice_id,v_order.patient_id,'pathology_result',coalesce(p_reported_at,now()),
    'Pathology result available',
    'Status '||p_status||' · overall flag '||p_overall_flag,
    'pathology_result',v_id,v_user,'PracticeCtrl',jsonb_build_object('order_id',v_order.id,'overall_flag',p_overall_flag));

  return v_id;
end $function$
;
revoke all on function public.record_pathology_result(uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,text,jsonb) from public, anon;
grant execute on function public.record_pathology_result(uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,text,jsonb) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.register_unsolicited_pathology_result(p_practice_id uuid, p_provider_id uuid, p_patient_id uuid, p_external_patient_ref text, p_external_order_ref text, p_external_result_ref text, p_accession_number text, p_overall_flag_hint text, p_summary text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_overall_flag_hint not in ('normal','abnormal','critical','unknown') then raise exception 'Invalid result flag hint'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','clinical_admin')) then
    raise exception 'Clinical write role required';
  end if;
  if not exists(select 1 from public.integration_provider p where p.id=p_provider_id and p.provider_type='pathology_lab') then
    raise exception 'Registered pathology provider required';
  end if;
  if p_patient_id is not null and not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then
    raise exception 'Patient is not in this practice';
  end if;

  insert into public.pathology_result_inbox(
    practice_id,provider_id,patient_id,external_patient_ref,external_order_ref,external_result_ref,
    accession_number,source_mode,status,overall_flag_hint,summary,created_by
  ) values(
    p_practice_id,p_provider_id,p_patient_id,nullif(trim(coalesce(p_external_patient_ref,'')),''),
    nullif(trim(coalesce(p_external_order_ref,'')),''),
    nullif(trim(coalesce(p_external_result_ref,'')),''),
    nullif(trim(coalesce(p_accession_number,'')),''),
    'manual',case when p_patient_id is null then 'unmatched' else 'patient_matched' end,
    p_overall_flag_hint,nullif(trim(coalesce(p_summary,'')),''),v_user
  ) returning id into v_id;

  insert into public.operations_work_item(
    practice_id,patient_id,category,source_entity_type,source_entity_id,title,description,priority,status,due_at,created_by
  ) values(
    p_practice_id,p_patient_id,'pathology','pathology_result_inbox',v_id,
    case p_overall_flag_hint when 'critical' then 'Critical unsolicited pathology result needs matching'
                             when 'abnormal' then 'Abnormal unsolicited pathology result needs matching'
                             else 'Unsolicited pathology result needs matching' end,
    'Confirm the patient and source order before filing this result into the clinical record.',
    case p_overall_flag_hint when 'critical' then 'urgent' when 'abnormal' then 'high' else 'normal' end,
    'open',
    now()+case p_overall_flag_hint when 'critical' then interval '1 hour' when 'abnormal' then interval '8 hours' else interval '24 hours' end,
    v_user
  )
  on conflict(practice_id,source_entity_type,source_entity_id,category) where source_entity_id is not null
  do nothing;

  insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
  values(p_practice_id,p_patient_id,'result',v_id,'unsolicited_result_staged',v_user,
    jsonb_build_object('overall_flag_hint',p_overall_flag_hint,'external_result_ref',p_external_result_ref));

  return v_id;
end $function$
;
revoke all on function public.register_unsolicited_pathology_result(uuid,uuid,uuid,text,text,text,text,text,text) from public, anon;
grant execute on function public.register_unsolicited_pathology_result(uuid,uuid,uuid,text,text,text,text,text,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.review_pathology_ai_summary(p_review_id uuid, p_decision text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_review public.pathology_ai_review%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_decision not in ('accept','discard') then raise exception 'Decision must be accept or discard'; end if;

  select * into v_review from public.pathology_ai_review where id=p_review_id for update;
  if not found then raise exception 'Pathology AI review not found'; end if;
  if v_review.status<>'completed' then raise exception 'Only a completed AI review can be accepted or discarded'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_review.practice_id and m.active and m.role='practitioner'
  ) then raise exception 'A practitioner must review the AI summary'; end if;

  update public.pathology_ai_review
  set status=case when p_decision='accept' then 'clinician_accepted' else 'discarded' end,
      reviewed_by=v_user,reviewed_at=now()
  where id=v_review.id;

  insert into public.pathology_audit_event(
    practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata
  ) values(
    v_review.practice_id,v_review.patient_id,'result',v_review.result_id,
    case when p_decision='accept' then 'ai_summary_accepted' else 'ai_summary_discarded' end,
    v_user,
    jsonb_build_object(
      'ai_review_id',v_review.id,
      'model_id',v_review.model_id,
      'confidence',v_review.confidence
    )
  );

  if p_decision='accept' then
    insert into public.crm_timeline_event(
      practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
    ) values(
      v_review.practice_id,v_review.patient_id,'pathology_ai_review',now(),
      'AI-assisted pathology summary reviewed',
      left(coalesce(v_review.summary,'AI-assisted pathology summary accepted by practitioner.'),1000),
      'pathology_result',v_review.result_id,v_user,'PracticeCtrl',
      jsonb_build_object(
        'ai_review_id',v_review.id,
        'human_reviewed',true,
        'model_id',v_review.model_id,
        'confidence',v_review.confidence
      )
    );
  end if;

  return jsonb_build_object(
    'review_id',v_review.id,
    'status',case when p_decision='accept' then 'clinician_accepted' else 'discarded' end,
    'reviewed_by',v_user,
    'reviewed_at',now()
  );
end $function$
;
revoke all on function public.review_pathology_ai_summary(uuid,text) from public, anon;
grant execute on function public.review_pathology_ai_summary(uuid,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.submit_pathology_order(p_order_id uuid, p_delivery_mode text DEFAULT 'manual'::text, p_environment text DEFAULT 'sandbox'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_order public.pathology_order%rowtype;
  v_provider public.integration_provider%rowtype;
  v_interface uuid;
  v_connection uuid;
  v_sandbox boolean;
  v_production boolean;
  v_ext_ref text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_delivery_mode not in ('manual','electronic') then raise exception 'Invalid delivery mode'; end if;
  if p_environment not in ('sandbox','production') then raise exception 'Invalid integration environment'; end if;

  select * into v_order from public.pathology_order where id=p_order_id for update;
  if not found then raise exception 'Pathology order not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_order.practice_id and m.active and m.role='practitioner'
  ) then raise exception 'Only a practitioner may submit a pathology order'; end if;
  if v_order.status not in ('draft','failed') then raise exception 'Only draft or failed pathology orders can be submitted'; end if;
  if not exists(select 1 from public.pathology_order_item i where i.order_id=v_order.id and i.status='requested') then
    raise exception 'Pathology order has no active requested tests';
  end if;

  select * into v_provider from public.integration_provider where id=v_order.provider_id;

  if p_delivery_mode='manual' then
    update public.pathology_order
    set status='ordered',delivery_mode='manual',transport_status='manual',
        ordered_by=v_user,ordered_at=now(),submitted_at=now(),
        treating_practitioner_user_id=coalesce(treating_practitioner_user_id,v_user),updated_at=now()
    where id=v_order.id;
    insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
    values(v_order.practice_id,v_order.patient_id,'order',v_order.id,'manual_order_issued',v_user,
      jsonb_build_object('provider',v_provider.slug,'order_category',v_order.order_category));
    return jsonb_build_object('order_id',v_order.id,'status','ordered','delivery_mode','manual','transport_status','manual','order_category',v_order.order_category);
  end if;

  select c.id,c.interface_id,coalesce(ac.executable_sandbox,false),coalesce(ac.executable_production,false)
  into v_connection,v_interface,v_sandbox,v_production
  from public.practice_integration_connection c
  join public.integration_adapter_capability ac
    on ac.provider_id=c.provider_id and ac.interface_id=c.interface_id and ac.capability_code='pathology_order_submit'
  where c.practice_id=v_order.practice_id and c.provider_id=v_order.provider_id
    and c.environment=p_environment and c.status in ('sandbox_active','production_ready','active')
  limit 1;

  if v_connection is null then raise exception 'No executable pathology order connection exists for this provider/environment'; end if;
  if p_environment='sandbox' and not v_sandbox then raise exception 'Pathology order submission is not executable in sandbox'; end if;
  if p_environment='production' and not v_production then raise exception 'Pathology order submission is not executable in production'; end if;

  if v_provider.slug='practicectrl-pathology-sandbox' and p_environment='sandbox' then
    v_ext_ref:='PCS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
    update public.pathology_order
    set status='submitted',delivery_mode='electronic',transport_status='accepted',
        interface_id=v_interface,connection_id=v_connection,external_order_ref=v_ext_ref,
        ordered_by=v_user,ordered_at=now(),submitted_at=now(),
        treating_practitioner_user_id=coalesce(treating_practitioner_user_id,v_user),updated_at=now()
    where id=v_order.id;
    insert into public.pathology_audit_event(practice_id,patient_id,entity_type,entity_id,event_type,actor_user_id,metadata)
    values(v_order.practice_id,v_order.patient_id,'order',v_order.id,'sandbox_order_accepted',v_user,
      jsonb_build_object('external_order_ref',v_ext_ref,'order_category',v_order.order_category));
    return jsonb_build_object('order_id',v_order.id,'status','submitted','delivery_mode','electronic','transport_status','accepted','external_order_ref',v_ext_ref,'synthetic',true,'order_category',v_order.order_category);
  end if;

  raise exception 'Provider transport is registered but no executable PracticeCtrl pathology adapter is deployed for this route';
end $function$
;
revoke all on function public.submit_pathology_order(uuid,text,text) from public, anon;
grant execute on function public.submit_pathology_order(uuid,text,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.sync_pathology_release_and_safety()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_policy public.pathology_release_policy%rowtype;
  v_owner uuid;
  v_base timestamptz;
  v_due timestamptz;
  v_hold text;
  v_case uuid;
begin
  if new.status not in ('final','corrected') or not new.is_current then
    if tg_op='UPDATE' and (not new.is_current or new.status='cancelled') then
      update public.pathology_safety_case
      set status='cancelled',resolved_at=coalesce(resolved_at,now()),updated_at=now()
      where result_id=new.id and status in ('open','acknowledged');
    end if;
    return new;
  end if;

  select * into v_policy from public.pathology_release_policy where practice_id=new.practice_id;
  if not found then
    perform private.seed_pathology_release_policy(new.practice_id);
    select * into v_policy from public.pathology_release_policy where practice_id=new.practice_id;
  end if;

  v_hold:=case
    when new.overall_flag='critical' and v_policy.hold_critical then 'Critical result requires explicit clinician review before patient release.'
    when new.status='corrected' and v_policy.hold_corrected_until_review then 'Corrected result requires clinician review before patient release.'
    else 'Awaiting clinician review and release approval.'
  end;

  insert into public.pathology_result_release(practice_id,result_id,status,hold_reason,release_after)
  values(
    new.practice_id,new.id,'held',v_hold,
    case when v_policy.default_mode='delayed_after_review' and v_policy.minimum_delay_minutes>0
         then now()+make_interval(mins=>v_policy.minimum_delay_minutes) else null end
  )
  on conflict(result_id) do update set
    status=case when public.pathology_result_release.status='released' then public.pathology_result_release.status else 'held' end,
    hold_reason=case when public.pathology_result_release.status='released' then public.pathology_result_release.hold_reason else excluded.hold_reason end,
    updated_at=now();

  select coalesce(o.treating_practitioner_user_id,o.ordered_by) into v_owner
  from public.pathology_order o where o.id=new.order_id;

  v_base:=coalesce(new.reported_at,new.received_at,new.created_at);
  v_due:=v_base+case new.overall_flag
    when 'critical' then interval '1 hour'
    when 'abnormal' then interval '24 hours'
    else interval '48 hours'
  end;

  insert into public.pathology_safety_case(
    practice_id,patient_id,result_id,severity,status,assigned_user_id,sla_due_at
  ) values(
    new.practice_id,new.patient_id,new.id,new.overall_flag,'open',v_owner,v_due
  )
  on conflict(result_id) do update set
    severity=excluded.severity,
    assigned_user_id=coalesce(public.pathology_safety_case.assigned_user_id,excluded.assigned_user_id),
    sla_due_at=excluded.sla_due_at,
    status=case when public.pathology_safety_case.status in ('resolved','cancelled') then public.pathology_safety_case.status else 'open' end,
    updated_at=now()
  returning id into v_case;

  if not exists(select 1 from public.pathology_safety_event e where e.safety_case_id=v_case and e.event_type='opened') then
    insert into public.pathology_safety_event(practice_id,safety_case_id,event_type,escalation_level,detail)
    values(new.practice_id,v_case,'opened',0,'Pathology result entered the clinician-review safety queue.');
  end if;

  return new;
end $function$
;
revoke all on function public.sync_pathology_release_and_safety() from public, anon;
grant execute on function public.sync_pathology_release_and_safety() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.sync_pathology_result_work_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_owner uuid; v_title text; v_desc text; v_priority text; v_due timestamptz; v_base timestamptz;
begin
  if new.status not in ('final','corrected') or not new.is_current then
    if tg_op='UPDATE' and not new.is_current then
      update public.operations_work_item
      set status='cancelled',updated_at=now()
      where practice_id=new.practice_id and source_entity_type='pathology_result' and source_entity_id=new.id
        and category='pathology' and status in ('open','in_progress','waiting','blocked');
    end if;
    return new;
  end if;

  select coalesce(treating_practitioner_user_id,ordered_by) into v_owner
  from public.pathology_order where id=new.order_id;

  v_priority:=case new.overall_flag when 'critical' then 'urgent' when 'abnormal' then 'high' else 'normal' end;
  v_base:=coalesce(new.reported_at,new.received_at,new.created_at);
  v_due:=v_base+case new.overall_flag when 'critical' then interval '1 hour' when 'abnormal' then interval '24 hours' else interval '48 hours' end;
  v_title:=case new.overall_flag when 'critical' then 'Critical pathology result requires review'
                                  when 'abnormal' then 'Abnormal pathology result requires review'
                                  else 'Pathology result requires acknowledgement' end;
  v_desc:='Review the current pathology result, document acknowledgement and record follow-up where required.';

  insert into public.operations_work_item(
    practice_id,patient_id,category,source_entity_type,source_entity_id,title,description,priority,status,owner_user_id,due_at,created_by
  ) values(
    new.practice_id,new.patient_id,'pathology','pathology_result',new.id,v_title,v_desc,v_priority,'open',v_owner,v_due,new.created_by
  )
  on conflict(practice_id,source_entity_type,source_entity_id,category)
    where source_entity_id is not null
  do update set
    title=excluded.title,description=excluded.description,priority=excluded.priority,
    status=case when public.operations_work_item.status='completed' then public.operations_work_item.status else 'open' end,
    owner_user_id=coalesce(public.operations_work_item.owner_user_id,excluded.owner_user_id),
    due_at=case when public.operations_work_item.status='completed' then public.operations_work_item.due_at else excluded.due_at end,
    updated_at=now();

  return new;
end $function$
;
revoke all on function public.sync_pathology_result_work_item() from public, anon;
grant execute on function public.sync_pathology_result_work_item() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.update_pathology_specimen_status(p_specimen_id uuid, p_to_status text, p_note text DEFAULT NULL::text, p_occurred_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_s public.pathology_specimen%rowtype;
  v_allowed boolean:=false;
  v_at timestamptz:=coalesce(p_occurred_at,now());
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_s from public.pathology_specimen where id=p_specimen_id for update;
  if not found then raise exception 'Pathology specimen not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_s.practice_id and m.active and m.role in ('practitioner','clinical_admin')
  ) then raise exception 'Clinical write role required'; end if;

  v_allowed:=case v_s.status
    when 'ordered' then p_to_status in ('collected','cancelled')
    when 'collected' then p_to_status in ('received_by_lab','rejected','cancelled')
    when 'received_by_lab' then p_to_status in ('processing','completed','rejected')
    when 'processing' then p_to_status in ('completed','rejected')
    when 'rejected' then p_to_status='collected'
    else false end;
  if not v_allowed then raise exception 'Invalid specimen status transition: % -> %',v_s.status,p_to_status; end if;

  update public.pathology_specimen
  set status=p_to_status,
      collected_at=case when p_to_status='collected' then v_at else collected_at end,
      received_by_lab_at=case when p_to_status='received_by_lab' then v_at else received_by_lab_at end,
      rejection_reason=case when p_to_status='rejected' then nullif(trim(coalesce(p_note,'')),'') else rejection_reason end,
      updated_at=now()
  where id=v_s.id;

  insert into public.pathology_specimen_event(practice_id,specimen_id,from_status,to_status,note,actor_user_id,occurred_at)
  values(v_s.practice_id,v_s.id,v_s.status,p_to_status,nullif(trim(coalesce(p_note,'')),''),v_user,v_at);

  if p_to_status='collected' then
    update public.pathology_order set status='collected',collected_at=coalesce(collected_at,v_at),updated_at=now()
    where id=v_s.order_id and status in ('ordered','submitted','acknowledged');
  elsif p_to_status in ('received_by_lab','processing') then
    update public.pathology_order set status='in_progress',updated_at=now()
    where id=v_s.order_id and status not in ('completed','cancelled','failed');
  elsif p_to_status='rejected' then
    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,title,description,priority,status,due_at,created_by
    ) values(
      v_s.practice_id,v_s.patient_id,'pathology','pathology_specimen',v_s.id,
      'Pathology specimen rejected',
      coalesce(nullif(trim(coalesce(p_note,'')),''),'Review rejection reason and arrange recollection where clinically appropriate.'),
      'high','open',now()+interval '4 hours',v_user
    )
    on conflict(practice_id,source_entity_type,source_entity_id,category) where source_entity_id is not null
    do update set status='open',completed_at=null,description=excluded.description,priority='high',due_at=excluded.due_at,updated_at=now();
  end if;

  return jsonb_build_object('specimen_id',v_s.id,'from_status',v_s.status,'to_status',p_to_status,'occurred_at',v_at);
end $function$
;
revoke all on function public.update_pathology_specimen_status(uuid,text,text,timestamp with time zone) from public, anon;
grant execute on function public.update_pathology_specimen_status(uuid,text,text,timestamp with time zone) to authenticated, service_role;
create or replace function public.create_pathology_order(p_practice_id uuid,p_patient_id uuid,p_encounter_id uuid,p_provider_id uuid,p_order_category text,p_priority text,p_fasting_required boolean,p_patient_instructions text,p_tests jsonb) returns uuid language sql set search_path to 'public','pg_temp' as $$ select public.create_pathology_order(p_practice_id,p_patient_id,p_encounter_id,p_provider_id,p_order_category,p_priority,null::text,p_fasting_required,p_patient_instructions,p_tests) $$;
revoke all on function public.create_pathology_order(uuid,uuid,uuid,uuid,text,text,boolean,text,jsonb) from public,anon;
grant execute on function public.create_pathology_order(uuid,uuid,uuid,uuid,text,text,boolean,text,jsonb) to authenticated,service_role;
CREATE TRIGGER pathology_order_item_assign_concept BEFORE INSERT OR UPDATE OF test_code, test_name, order_id ON public.pathology_order_item FOR EACH ROW EXECUTE FUNCTION pathology_assign_order_item_concept();
CREATE TRIGGER pathology_order_item_consistency BEFORE INSERT OR UPDATE ON public.pathology_order_item FOR EACH ROW EXECUTE FUNCTION pathology_enforce_order_item_consistency();
CREATE TRIGGER pathology_result_consistency BEFORE INSERT OR UPDATE OF practice_id, order_id, patient_id, provider_id, encounter_id ON public.pathology_result FOR EACH ROW EXECUTE FUNCTION pathology_enforce_result_consistency();
CREATE TRIGGER pathology_result_create_review_work AFTER INSERT OR UPDATE OF status, overall_flag ON public.pathology_result FOR EACH ROW EXECUTE FUNCTION sync_pathology_result_work_item();
CREATE TRIGGER pathology_result_revision_guard BEFORE INSERT OR UPDATE OF version_no, correction_of_result_id, status, practice_id, patient_id, order_id, provider_id ON public.pathology_result FOR EACH ROW EXECUTE FUNCTION pathology_result_revision_guard();
CREATE TRIGGER pathology_result_sync_release_safety AFTER INSERT OR UPDATE OF status, overall_flag, is_current ON public.pathology_result FOR EACH ROW EXECUTE FUNCTION sync_pathology_release_and_safety();
CREATE TRIGGER pathology_ack_consistency BEFORE INSERT OR UPDATE ON public.pathology_result_acknowledgement FOR EACH ROW EXECUTE FUNCTION pathology_enforce_ack_consistency();
CREATE TRIGGER pathology_document_consistency BEFORE INSERT OR UPDATE ON public.pathology_result_document FOR EACH ROW EXECUTE FUNCTION pathology_enforce_document_consistency();
CREATE TRIGGER pathology_result_item_assign_concept BEFORE INSERT OR UPDATE OF test_code, test_name, result_id ON public.pathology_result_item FOR EACH ROW EXECUTE FUNCTION pathology_assign_result_item_concept();
CREATE TRIGGER pathology_result_item_consistency BEFORE INSERT OR UPDATE ON public.pathology_result_item FOR EACH ROW EXECUTE FUNCTION pathology_enforce_result_item_consistency();
CREATE TRIGGER pathology_result_item_recompute_flag AFTER INSERT OR DELETE OR UPDATE OF flag ON public.pathology_result_item FOR EACH ROW EXECUTE FUNCTION pathology_recompute_overall_flag();
create trigger practice_seed_pathology_sandbox_connection after insert on public.practice for each row execute function private.seed_pathology_sandbox_connection_trigger();
create trigger practice_seed_pathology_release_policy after insert on public.practice for each row execute function private.seed_pathology_release_policy_trigger();
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('pathology-result-files','pathology-result-files',false,15728640,array['application/pdf','image/jpeg','image/png']) on conflict(id) do nothing;
create policy "pathology_result_files_insert" on storage.objects for insert to authenticated with check (((bucket_id = 'pathology-result-files'::text) AND ((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = ((storage.foldername(objects.name))[1])::uuid) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role])))))));
create policy "pathology_result_files_read" on storage.objects for select to authenticated using (((bucket_id = 'pathology-result-files'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = ((storage.foldername(objects.name))[1])::uuid) AND m.active AND (m.role = ANY (ARRAY['practitioner'::practice_staff_role, 'clinical_admin'::practice_staff_role, 'practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role, 'auditor'::practice_staff_role])))))));
commit;
