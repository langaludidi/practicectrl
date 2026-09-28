
begin;

create table if not exists public.appointment_request_event (
  id uuid primary key default gen_random_uuid(),
  appointment_request_id uuid not null references public.appointment_request(id) on delete cascade,
  event_type text not null check (event_type in ('created','status_changed','assigned','pms_confirmed','closed','other')),
  actor_user_id uuid references auth.users(id) on delete set null,
  from_status text,
  to_status text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists appointment_request_event_request_idx
  on public.appointment_request_event(appointment_request_id,created_at desc);
create index if not exists appointment_request_event_actor_idx
  on public.appointment_request_event(actor_user_id) where actor_user_id is not null;

alter table public.appointment_request_event enable row level security;
revoke all on table public.appointment_request_event from anon,authenticated;
grant select on table public.appointment_request_event to authenticated;

create policy appointment_request_event_staff_read
on public.appointment_request_event for select to authenticated
using (exists (
  select 1
  from public.appointment_request r
  join public.practice_staff_member m on m.practice_id=r.practice_id
  where r.id=appointment_request_event.appointment_request_id
    and m.user_id=(select auth.uid()) and m.active
));

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
  if p_status not in ('New','Contacted','Confirmed in PMS','Alternative Offered','Unable to Reach','Closed','Duplicate') then raise exception 'Invalid appointment-request status'; end if;

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

  insert into public.appointment_request_event(
    appointment_request_id,event_type,actor_user_id,from_status,to_status,metadata
  ) values(
    p_request_id,
    case when p_status='Confirmed in PMS' then 'pms_confirmed'
         when p_status in ('Closed','Duplicate') then 'closed'
         else 'status_changed' end,
    v_user,v_req.status,p_status,
    jsonb_build_object('pms_reference',case when p_status='Confirmed in PMS' then coalesce(nullif(trim(p_pms_reference),''),v_req.pms_reference) else null end)
  );

  return p_request_id;
end;
$$;
revoke all on function public.update_appointment_request_status(uuid,text,text) from public,anon;
grant execute on function public.update_appointment_request_status(uuid,text,text) to authenticated;

create or replace function public.create_communication_draft(
  p_practice_id uuid,
  p_patient_id uuid,
  p_thread_type text,
  p_channel text,
  p_recipient text,
  p_subject text,
  p_body text,
  p_contains_clinical_detail boolean default false
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_role public.practice_staff_role;
  v_thread_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_thread_type not in ('administrative','appointment','billing','claim','referral','other') then raise exception 'Invalid thread type'; end if;
  if p_channel not in ('email','sms','whatsapp','phone','internal') then raise exception 'Invalid communication channel'; end if;
  if length(trim(coalesce(p_body,'')))<1 then raise exception 'Message body is required'; end if;

  select role into v_role
  from public.practice_staff_member
  where user_id=v_user and practice_id=p_practice_id and active;

  if v_role is null or v_role='auditor' then raise exception 'Active staff role required'; end if;
  if p_contains_clinical_detail and v_role not in ('practitioner','clinical_admin','practice_manager','system_admin') then
    raise exception 'This role cannot draft communication containing clinical detail';
  end if;

  if p_patient_id is not null and not exists (
    select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id
  ) then raise exception 'Patient is not in this practice'; end if;

  insert into public.communication_thread(
    practice_id,patient_id,thread_type,subject,status,created_by,last_activity_at
  ) values(
    p_practice_id,p_patient_id,p_thread_type,nullif(trim(coalesce(p_subject,'')),''),'open',v_user,now()
  ) returning id into v_thread_id;

  insert into public.communication_message(
    thread_id,direction,channel,status,recipient,subject,body,contains_clinical_detail,created_by
  ) values(
    v_thread_id,'outbound',p_channel,'draft',nullif(trim(coalesce(p_recipient,'')),''),
    nullif(trim(coalesce(p_subject,'')),''),trim(p_body),p_contains_clinical_detail,v_user
  );

  return v_thread_id;
end;
$$;
revoke all on function public.create_communication_draft(uuid,uuid,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.create_communication_draft(uuid,uuid,text,text,text,text,text,boolean) to authenticated;

create or replace function public.update_operations_work_item(
  p_work_item_id uuid,
  p_status text,
  p_note text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_item public.operations_work_item%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_status not in ('open','in_progress','waiting','blocked','completed','cancelled') then raise exception 'Invalid work-item status'; end if;

  select * into v_item from public.operations_work_item where id=p_work_item_id for update;
  if not found then raise exception 'Work item not found or not accessible'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_item.practice_id and m.active and m.role<>'auditor'
  ) then raise exception 'Active operations role required'; end if;

  if p_status='blocked' and length(trim(coalesce(p_note,v_item.blocked_reason,'')))<3 then
    raise exception 'A blocked reason is required';
  end if;

  update public.operations_work_item
  set status=p_status,
      blocked_reason=case when p_status='blocked' then coalesce(nullif(trim(p_note),''),blocked_reason) when v_item.status='blocked' then null else blocked_reason end,
      completed_at=case when p_status='completed' then coalesce(completed_at,now()) when v_item.status='completed' and p_status<>'completed' then null else completed_at end,
      updated_at=now()
  where id=p_work_item_id;

  insert into public.operations_work_event(work_item_id,event_type,actor_user_id,metadata)
  values(
    p_work_item_id,
    case when p_status='completed' then 'completed' when v_item.status='completed' and p_status<>'completed' then 'reopened' else 'status_changed' end,
    v_user,
    jsonb_build_object('from_status',v_item.status,'to_status',p_status,'note',nullif(trim(coalesce(p_note,'')),''))
  );

  return p_work_item_id;
end;
$$;
revoke all on function public.update_operations_work_item(uuid,text,text) from public,anon;
grant execute on function public.update_operations_work_item(uuid,text,text) to authenticated;

commit;
