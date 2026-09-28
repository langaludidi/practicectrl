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
