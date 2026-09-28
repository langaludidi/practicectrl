-- Staging change for the PMS appointment source of truth.
-- This migration assumes all existing PracticeCtrl bookings and legacy request statuses
-- have been reconciled in the PMS. At application time staging had zero of each.
-- Reversible grants/policies are deliberately scoped to the appointment workflow.

revoke execute on function public.create_practice_appointment(uuid,uuid,uuid,uuid,timestamptz,uuid,text,text,text,uuid) from public, anon, authenticated;
revoke execute on function public.reschedule_practice_appointment(uuid,timestamptz,uuid,text) from public, anon, authenticated;
revoke execute on function public.update_practice_appointment_status(uuid,text,text) from public, anon, authenticated;
revoke execute on function public.next_appointment_number(uuid,date) from public, anon, authenticated;
revoke insert, update on public.practice_appointment from authenticated;
revoke insert on public.appointment_event from authenticated;
revoke insert, update on public.appointment_sequence from authenticated;
revoke insert, update, delete on public.appointment_waitlist from authenticated;

alter table public.appointment_request drop constraint appointment_request_status_check;
alter table public.appointment_request add constraint appointment_request_status_check
  check (status in ('New', 'Contacted', 'Confirmed in PMS', 'Alternative Offered', 'Unable to Reach', 'Closed', 'Duplicate'));
alter table public.appointment_request add constraint appointment_request_confirmed_pms_reference_check
  check (status <> 'Confirmed in PMS' or nullif(btrim(pms_reference), '') is not null);

drop policy if exists appointment_request_staff_update on public.appointment_request;
create policy appointment_request_staff_update on public.appointment_request for update to authenticated
  using (
    (select auth.jwt())->>'aal' = 'aal2'
    and (select coalesce(current_setting('request.path', true), '')) = '/rpc/update_appointment_request_status'
    and exists (
      select 1 from public.practice_staff_member m
      where m.user_id = (select auth.uid()) and m.practice_id = appointment_request.practice_id
        and m.active and m.role in ('reception', 'practice_manager', 'clinical_admin', 'system_admin')
    )
  )
  with check (
    (select auth.jwt())->>'aal' = 'aal2'
    and (select coalesce(current_setting('request.path', true), '')) = '/rpc/update_appointment_request_status'
    and exists (
      select 1 from public.practice_staff_member m
      where m.user_id = (select auth.uid()) and m.practice_id = appointment_request.practice_id
        and m.active and m.role in ('reception', 'practice_manager', 'clinical_admin', 'system_admin')
    )
  );

drop policy if exists appointment_request_booking_event_insert on public.appointment_request_event;
drop policy if exists appointment_request_status_event_insert on public.appointment_request_event;
create policy appointment_request_status_event_insert on public.appointment_request_event
  for insert to authenticated with check (
    (select auth.jwt())->>'aal' = 'aal2'
    and (select coalesce(current_setting('request.path', true), '')) = '/rpc/update_appointment_request_status'
    and actor_user_id = (select auth.uid())
    and exists (
      select 1 from public.appointment_request r
      join public.practice_staff_member m on m.practice_id = r.practice_id
      where r.id = appointment_request_event.appointment_request_id and m.user_id = (select auth.uid())
        and m.active and m.role in ('reception', 'practice_manager', 'clinical_admin', 'system_admin')
    )
  );
grant insert on public.appointment_request_event to authenticated;

create or replace function public.update_appointment_request_status(
  p_request_id uuid, p_status text, p_pms_reference text default null
) returns uuid language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_user uuid := (select auth.uid());
  v_req public.appointment_request%rowtype;
  v_reference text := nullif(btrim(p_pms_reference), '');
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'), '') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_status not in ('New', 'Contacted', 'Confirmed in PMS', 'Alternative Offered', 'Unable to Reach', 'Closed', 'Duplicate')
    then raise exception 'Invalid appointment-request status'; end if;
  select * into v_req from public.appointment_request where id = p_request_id for update;
  if not found then raise exception 'Appointment request not found or not accessible'; end if;
  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id = v_user and m.practice_id = v_req.practice_id and m.active
      and m.role in ('reception', 'practice_manager', 'clinical_admin', 'system_admin')
  ) then raise exception 'Request-management role required'; end if;
  if v_req.status in ('Confirmed in PMS', 'Booked in PracticeCtrl', 'Closed', 'Duplicate')
    then raise exception 'This request is closed. Verify changes in the PMS and contact an administrator for correction'; end if;
  if p_status = 'Confirmed in PMS' and v_reference is null
    then raise exception 'A PMS appointment reference is required'; end if;
  if length(coalesce(v_reference, '')) > 120 then raise exception 'PMS reference is too long'; end if;
  if p_status = v_req.status then return p_request_id; end if;

  update public.appointment_request
  set status = p_status,
      pms_reference = case when p_status = 'Confirmed in PMS' then v_reference else pms_reference end,
      contacted_at = case when p_status = 'Contacted' then coalesce(contacted_at, now()) else contacted_at end,
      confirmed_at = case when p_status = 'Confirmed in PMS' then now() else confirmed_at end,
      closed_at = case when p_status in ('Confirmed in PMS', 'Closed', 'Duplicate') then now() else closed_at end,
      updated_at = now()
  where id = p_request_id;

  insert into public.appointment_request_event(appointment_request_id, event_type, actor_user_id, from_status, to_status, metadata)
  values (p_request_id, case when p_status = 'Confirmed in PMS' then 'pms_confirmed' else 'status_changed' end,
          v_user, v_req.status, p_status,
          case when p_status = 'Confirmed in PMS' then jsonb_build_object('pms_reference', v_reference) else '{}'::jsonb end);
  return p_request_id;
end $$;
revoke all on function public.update_appointment_request_status(uuid,text,text) from public, anon;
grant execute on function public.update_appointment_request_status(uuid,text,text) to authenticated;
