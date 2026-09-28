
create or replace function public.create_practice_appointment(p_practice_id uuid,p_patient_id uuid,p_practitioner_id uuid,p_appointment_type_id uuid,p_starts_at timestamptz,p_location_id uuid default null,p_booking_source text default 'internal',p_reason text default null,p_notes text default null,p_appointment_request_id uuid default null) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid()); v_type public.appointment_type%rowtype; v_id uuid:=gen_random_uuid(); v_end timestamptz; v_number text; v_request_status text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Appointment scheduling role required'; end if;
 if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id and p.status='active') then raise exception 'Active patient not found in selected practice'; end if;
 if not exists(select 1 from public.practitioner_profile p where p.id=p_practitioner_id and p.practice_id=p_practice_id and p.active) then raise exception 'Active practitioner not found in selected practice'; end if;
 select * into v_type from public.appointment_type where id=p_appointment_type_id and practice_id=p_practice_id and active; if not found then raise exception 'Active appointment type not found in selected practice'; end if;
 if p_starts_at<now()-interval '1 day' then raise exception 'Appointment start is too far in the past'; end if;
 v_end:=p_starts_at+make_interval(mins=>v_type.duration_minutes);
 if exists(select 1 from public.practitioner_schedule_exception e where e.practice_id=p_practice_id and e.practitioner_id=p_practitioner_id and e.exception_type='unavailable' and tstzrange(e.starts_at,e.ends_at,'[)')&&tstzrange(p_starts_at,v_end,'[)')) then raise exception 'Practitioner is unavailable during the requested time'; end if;
 v_number:=public.next_appointment_number(p_practice_id,p_starts_at::date);
 insert into public.practice_appointment(id,practice_id,appointment_number,patient_id,practitioner_id,appointment_type_id,location_id,appointment_request_id,starts_at,ends_at,booking_source,reason,notes,created_by,updated_by) values(v_id,p_practice_id,v_number,p_patient_id,p_practitioner_id,p_appointment_type_id,p_location_id,p_appointment_request_id,p_starts_at,v_end,p_booking_source,p_reason,p_notes,v_user,v_user);
 insert into public.appointment_event(appointment_id,event_type,actor_user_id,to_status,metadata) values(v_id,'created',v_user,'booked',jsonb_build_object('appointment_number',v_number,'starts_at',p_starts_at,'ends_at',v_end));
 if p_appointment_request_id is not null then
   select status into v_request_status from public.appointment_request where id=p_appointment_request_id and practice_id=p_practice_id for update; if not found then raise exception 'Appointment request not found in selected practice'; end if;
   update public.appointment_request set patient_id=coalesce(patient_id,p_patient_id),status='Booked in PracticeCtrl',confirmed_at=coalesce(confirmed_at,now()),closed_at=coalesce(closed_at,now()),updated_at=now() where id=p_appointment_request_id;
   insert into public.appointment_request_event(appointment_request_id,event_type,actor_user_id,from_status,to_status,metadata) values(p_appointment_request_id,'status_changed',v_user,v_request_status,'Booked in PracticeCtrl',jsonb_build_object('appointment_id',v_id,'appointment_number',v_number,'reason','PracticeCtrl appointment created'));
 end if;
 return v_id;
exception when exclusion_violation then raise exception 'The practitioner or room is already booked during this time';
end $$;

