
create or replace function public.issue_patient_intake(
 p_practice_id uuid,
 p_appointment_id uuid default null,
 p_existing_patient_id uuid default null,
 p_patient_display_name text default null,
 p_patient_phone_hint text default null,
 p_patient_email_hint text default null,
 p_expires_hours integer default 72,
 p_source text default 'online'
) returns table(intake_session_id uuid,intake_token text,expires_at timestamptz)
language plpgsql security invoker set search_path=public,extensions,pg_temp as $$
declare v_user uuid:=(select auth.uid()); v_id uuid:=gen_random_uuid(); v_token text; v_exp timestamptz;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required'; end if;
 if p_expires_hours<1 or p_expires_hours>336 then raise exception 'Expiry must be between 1 and 336 hours'; end if;
 if p_source not in('online','tablet','paper','staff_capture') then raise exception 'Invalid intake source'; end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Patient intake role required'; end if;
 if p_appointment_id is not null and not exists(select 1 from public.practice_appointment a where a.id=p_appointment_id and a.practice_id=p_practice_id) then raise exception 'Appointment not found in selected practice'; end if;
 if p_existing_patient_id is not null and not exists(select 1 from public.crm_patient p where p.id=p_existing_patient_id and p.practice_id=p_practice_id) then raise exception 'Patient not found in selected practice'; end if;
 v_token:=encode(gen_random_bytes(32),'hex'); v_exp:=now()+make_interval(hours=>p_expires_hours);
 insert into public.patient_intake_session(id,practice_id,appointment_id,existing_patient_id,source,status,token_hash,token_expires_at,patient_display_name,patient_phone_hint,patient_email_hint,created_by)
 values(v_id,p_practice_id,p_appointment_id,p_existing_patient_id,p_source,case when p_source in('paper','staff_capture') then 'in_progress' else 'invited' end,encode(digest(v_token,'sha256'),'hex'),v_exp,p_patient_display_name,p_patient_phone_hint,p_patient_email_hint,v_user);
 insert into public.patient_intake_event(intake_session_id,event_type,actor_type,actor_user_id,metadata)
 values(v_id,'issued','staff',v_user,jsonb_build_object('source',p_source,'expires_at',v_exp,'appointment_id',p_appointment_id));
 return query select v_id,v_token,v_exp;
end $$;
revoke all on function public.issue_patient_intake(uuid,uuid,uuid,text,text,text,integer,text) from public,anon;
grant execute on function public.issue_patient_intake(uuid,uuid,uuid,text,text,text,integer,text) to authenticated;
grant insert on public.patient_intake_event to authenticated;
create policy intake_event_staff_insert on public.patient_intake_event for insert to authenticated with check(((select auth.jwt())->>'aal')='aal2' and actor_type='staff' and actor_user_id=(select auth.uid()) and exists(select 1 from public.patient_intake_session s join public.practice_staff_member m on m.practice_id=s.practice_id where s.id=patient_intake_event.intake_session_id and m.user_id=(select auth.uid()) and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));

