
begin;

create or replace function public.create_internal_appointment_request(
  p_practice_id uuid,
  p_patient_id uuid,
  p_requester_name text,
  p_requester_phone text,
  p_requester_email text,
  p_requested_service text,
  p_preferred_date date,
  p_preferred_time text,
  p_message text
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_requester_name,'')))<2 then raise exception 'Requester name is required'; end if;
  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('reception','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'Request-management role required'; end if;
  if p_patient_id is not null and not exists (
    select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id
  ) then raise exception 'Patient is not in this practice'; end if;

  insert into public.appointment_request(
    practice_id,patient_id,source,requester_name,requester_phone,requester_email,
    requested_service,preferred_date,preferred_time,message,status,created_by
  ) values(
    p_practice_id,p_patient_id,'internal',trim(p_requester_name),
    nullif(trim(coalesce(p_requester_phone,'')),''),
    nullif(trim(coalesce(p_requester_email,'')),''),
    nullif(trim(coalesce(p_requested_service,'')),''),
    p_preferred_date,nullif(trim(coalesce(p_preferred_time,'')),''),
    nullif(trim(coalesce(p_message,'')),''),'New',v_user
  ) returning id into v_id;

  insert into public.appointment_request_event(
    appointment_request_id,event_type,actor_user_id,from_status,to_status,metadata
  ) values(
    v_id,'created',v_user,null,'New',jsonb_build_object('source','internal')
  );

  return v_id;
end;
$$;
revoke all on function public.create_internal_appointment_request(uuid,uuid,text,text,text,text,date,text,text) from public,anon;
grant execute on function public.create_internal_appointment_request(uuid,uuid,text,text,text,text,date,text,text) to authenticated;

create or replace function public.create_crm_follow_up_task(
  p_practice_id uuid,
  p_patient_id uuid,
  p_category text,
  p_title text,
  p_description text,
  p_priority text,
  p_due_at timestamptz
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_category not in ('follow_up','recall','referral','appointment','documentation','billing','claim','communication','other') then raise exception 'Invalid CRM task category'; end if;
  if p_priority not in ('low','normal','high','urgent') then raise exception 'Invalid priority'; end if;
  if length(trim(coalesce(p_title,'')))<2 then raise exception 'Task title is required'; end if;
  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role<>'auditor'
  ) then raise exception 'Active staff role required'; end if;
  if p_patient_id is not null and not exists (
    select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id
  ) then raise exception 'Patient is not in this practice'; end if;

  insert into public.crm_task(
    practice_id,patient_id,category,title,description,priority,status,
    owner_user_id,due_at,created_by
  ) values(
    p_practice_id,p_patient_id,p_category,trim(p_title),
    nullif(trim(coalesce(p_description,'')),''),p_priority,'open',
    v_user,p_due_at,v_user
  ) returning id into v_id;

  if p_patient_id is not null then
    insert into public.crm_timeline_event(
      practice_id,patient_id,event_type,title,summary,entity_type,entity_id,actor_user_id,source_system
    ) values(
      p_practice_id,p_patient_id,'task','Follow-up task: '||trim(p_title),
      nullif(trim(coalesce(p_description,'')),''),'crm_task',v_id,v_user,'PracticeCtrl'
    );
  end if;

  return v_id;
end;
$$;
revoke all on function public.create_crm_follow_up_task(uuid,uuid,text,text,text,text,timestamptz) from public,anon;
grant execute on function public.create_crm_follow_up_task(uuid,uuid,text,text,text,text,timestamptz) to authenticated;

create or replace function public.sync_crm_task_work_item()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_category text;
  v_status text;
begin
  v_category := case
    when new.category in ('follow_up','recall') then 'patient_follow_up'
    when new.category='appointment' then 'appointment_request'
    when new.category in ('referral','documentation','billing','claim','communication') then new.category
    else 'other'
  end;
  v_status := case
    when new.status='open' then 'open'
    when new.status='in_progress' then 'in_progress'
    when new.status='waiting' then 'waiting'
    when new.status='completed' then 'completed'
    when new.status='cancelled' then 'cancelled'
    else 'open'
  end;

  insert into public.operations_work_item(
    practice_id,patient_id,category,source_entity_type,source_entity_id,
    title,description,priority,status,owner_user_id,due_at,completed_at,created_by
  ) values(
    new.practice_id,new.patient_id,v_category,'crm_task',new.id,
    new.title,new.description,new.priority,v_status,new.owner_user_id,new.due_at,
    case when v_status='completed' then coalesce(new.completed_at,now()) else null end,
    new.created_by
  )
  on conflict (practice_id,source_entity_type,source_entity_id,category)
    where source_entity_id is not null
  do update set
    patient_id=excluded.patient_id,
    title=excluded.title,
    description=excluded.description,
    priority=excluded.priority,
    status=excluded.status,
    owner_user_id=excluded.owner_user_id,
    due_at=excluded.due_at,
    completed_at=excluded.completed_at,
    updated_at=now();

  return new;
end;
$$;

drop trigger if exists trg_sync_crm_task_work_item on public.crm_task;
create trigger trg_sync_crm_task_work_item
after insert or update of status,priority,owner_user_id,due_at,title,description
on public.crm_task
for each row execute function public.sync_crm_task_work_item();

commit;
