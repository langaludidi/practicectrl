
begin;

create or replace function public.audit_appointment_request_change()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid := (select auth.uid());
begin
  if tg_op='INSERT' then
    insert into public.appointment_request_event(
      appointment_request_id,event_type,actor_user_id,from_status,to_status,metadata
    ) values(
      new.id,'created',coalesce(v_actor,new.created_by),null,new.status,
      jsonb_build_object('source',new.source)
    );
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to then
    insert into public.appointment_request_event(
      appointment_request_id,event_type,actor_user_id,from_status,to_status,metadata
    ) values(
      new.id,'assigned',v_actor,old.status,new.status,
      jsonb_build_object('previous_assignee',old.assigned_to,'new_assignee',new.assigned_to)
    );
  end if;

  if new.status is distinct from old.status then
    insert into public.appointment_request_event(
      appointment_request_id,event_type,actor_user_id,from_status,to_status,metadata
    ) values(
      new.id,
      case when new.status='Confirmed in PMS' then 'pms_confirmed'
           when new.status in ('Closed','Duplicate') then 'closed'
           else 'status_changed' end,
      v_actor,old.status,new.status,
      jsonb_build_object(
        'pms_reference',case when new.status='Confirmed in PMS' then new.pms_reference else null end
      )
    );
  end if;

  return new;
end;
$$;

revoke all on function public.audit_appointment_request_change() from public,anon,authenticated;

drop trigger if exists trg_audit_appointment_request_change on public.appointment_request;
create trigger trg_audit_appointment_request_change
after insert or update of status,assigned_to,pms_reference
on public.appointment_request
for each row execute function public.audit_appointment_request_change();

create or replace function public.update_appointment_request_status(
  p_request_id uuid,
  p_status text,
  p_pms_reference text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_req public.appointment_request%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_status not in ('New','Contacted','Confirmed in PMS','Alternative Offered','Unable to Reach','Closed','Duplicate') then
    raise exception 'Invalid appointment-request status';
  end if;

  select * into v_req from public.appointment_request where id=p_request_id for update;
  if not found then raise exception 'Appointment request not found or not accessible'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_req.practice_id and m.active
      and m.role in ('reception','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'Request-management role required'; end if;

  if p_status='Confirmed in PMS' and length(trim(coalesce(p_pms_reference,v_req.pms_reference,'')))<1 then
    raise exception 'A PMS reference is required before confirming the appointment';
  end if;

  update public.appointment_request
  set status=p_status,
      pms_reference=case when p_status='Confirmed in PMS' then coalesce(nullif(trim(p_pms_reference),''),pms_reference) else pms_reference end,
      contacted_at=case when p_status='Contacted' then coalesce(contacted_at,now()) else contacted_at end,
      confirmed_at=case when p_status='Confirmed in PMS' then coalesce(confirmed_at,now()) else confirmed_at end,
      closed_at=case when p_status in ('Closed','Duplicate') then coalesce(closed_at,now()) else closed_at end,
      updated_at=now()
  where id=p_request_id;

  return p_request_id;
end;
$$;

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

  return v_id;
end;
$$;

revoke all on function public.create_source_dataset_release_draft(uuid,text,text,date,date,date,text,text,text)
from public,anon,authenticated;
drop function public.create_source_dataset_release_draft(uuid,text,text,date,date,date,text,text,text);

commit;

