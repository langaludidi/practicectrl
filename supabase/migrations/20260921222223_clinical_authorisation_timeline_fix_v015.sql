create or replace function public.sign_clinical_note(p_note_id uuid) returns uuid
language plpgsql
security invoker
set search_path=public,extensions,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_note public.clinical_note%rowtype;
  v_hash text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_note from public.clinical_note where id=p_note_id for update;
  if not found then raise exception 'Clinical note not found or not accessible'; end if;
  if v_note.status<>'draft' then raise exception 'Only a draft clinical note can be signed'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_note.practice_id and m.active and m.role='practitioner') then raise exception 'Practitioner role required to sign a clinical note'; end if;
  if v_note.author_user_id<>v_user and not exists(select 1 from public.practice_encounter e where e.id=v_note.encounter_id and e.practitioner_user_id=v_user) then raise exception 'Only the author or encounter practitioner may sign this note'; end if;
  if length(trim(coalesce(v_note.assessment,v_note.narrative,'')))<2 then raise exception 'Clinical assessment or narrative is required before signing'; end if;
  v_hash:=encode(extensions.digest(concat_ws('|',v_note.practice_id::text,v_note.patient_id::text,v_note.encounter_id::text,v_note.note_type,coalesce(v_note.title,''),coalesce(v_note.subjective,''),coalesce(v_note.objective,''),coalesce(v_note.assessment,''),coalesce(v_note.plan,''),coalesce(v_note.narrative,''),v_note.structured_data::text),'sha256'),'hex');
  update public.clinical_note set status='signed',signed_by=v_user,signed_at=now(),content_sha256=v_hash,updated_at=now() where id=p_note_id;
  insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata) values(p_note_id,'signed',v_user,jsonb_build_object('content_sha256',v_hash));
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(v_note.practice_id,v_note.patient_id,'clinical_note_signed',now(),'Clinical note signed',coalesce(v_note.title,initcap(replace(v_note.note_type,'_',' '))),'clinical_note',p_note_id,v_user,'PracticeCtrl',jsonb_build_object('content_sha256',v_hash));
  return p_note_id;
end;
$$;

create or replace function public.create_scheme_authorisation(
  p_practice_id uuid,
  p_patient_id uuid,
  p_membership_id uuid,
  p_encounter_id uuid,
  p_request_reference text,
  p_request_date date,
  p_requested_amount numeric,
  p_requested_units numeric,
  p_notes text
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_membership public.crm_patient_scheme_membership%rowtype;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')) then raise exception 'Authorisation-management role required'; end if;
  select * into v_membership from public.crm_patient_scheme_membership where id=p_membership_id and practice_id=p_practice_id and patient_id=p_patient_id;
  if not found then raise exception 'Patient scheme membership not found in the selected practice'; end if;
  if p_encounter_id is not null and not exists(select 1 from public.practice_encounter e where e.id=p_encounter_id and e.practice_id=p_practice_id and e.patient_id=p_patient_id) then raise exception 'Encounter does not belong to this patient/practice'; end if;
  insert into public.scheme_authorisation(practice_id,patient_id,membership_id,encounter_id,medical_scheme_id,medical_scheme_option_id,request_reference,status,request_date,requested_amount,requested_units,notes,created_by,updated_by)
  values(p_practice_id,p_patient_id,p_membership_id,p_encounter_id,v_membership.medical_scheme_id,v_membership.medical_scheme_option_id,nullif(trim(coalesce(p_request_reference,'')),''),'requested',coalesce(p_request_date,current_date),p_requested_amount,p_requested_units,nullif(trim(coalesce(p_notes,'')),''),v_user,v_user)
  returning id into v_id;
  insert into public.scheme_authorisation_event(authorisation_id,event_type,actor_user_id,metadata) values(v_id,'requested',v_user,jsonb_build_object('request_reference',p_request_reference));
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(p_practice_id,p_patient_id,'scheme_authorisation_requested',now(),'Medical scheme authorisation requested',coalesce(p_request_reference,'Authorisation request'),'scheme_authorisation',v_id,v_user,'PracticeCtrl','{}'::jsonb);
  return v_id;
end;
$$;

create or replace function public.update_scheme_authorisation_status(
  p_authorisation_id uuid,
  p_status text,
  p_authorisation_number text,
  p_decision_date date,
  p_effective_from date,
  p_effective_to date,
  p_approved_amount numeric,
  p_approved_units numeric,
  p_conditions text,
  p_decline_reason text
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_auth public.scheme_authorisation%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_status not in ('requested','pending','approved','partially_approved','declined','expired','cancelled') then raise exception 'Invalid authorisation status'; end if;
  select * into v_auth from public.scheme_authorisation where id=p_authorisation_id for update;
  if not found then raise exception 'Authorisation not found or not accessible'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_auth.practice_id and m.active and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')) then raise exception 'Authorisation-management role required'; end if;
  if p_status in ('approved','partially_approved') and length(trim(coalesce(p_authorisation_number,v_auth.authorisation_number,'')))<1 then raise exception 'Authorisation number is required for an approval'; end if;
  if p_effective_to is not null and p_effective_from is not null and p_effective_to<p_effective_from then raise exception 'Effective-to date cannot precede effective-from date'; end if;
  update public.scheme_authorisation set
    status=p_status,
    authorisation_number=coalesce(nullif(trim(coalesce(p_authorisation_number,'')),''),authorisation_number),
    decision_date=coalesce(p_decision_date,decision_date),
    effective_from=coalesce(p_effective_from,effective_from),
    effective_to=coalesce(p_effective_to,effective_to),
    approved_amount=coalesce(p_approved_amount,approved_amount),
    approved_units=coalesce(p_approved_units,approved_units),
    conditions=coalesce(nullif(trim(coalesce(p_conditions,'')),''),conditions),
    decline_reason=case when p_status='declined' then coalesce(nullif(trim(coalesce(p_decline_reason,'')),''),decline_reason) else decline_reason end,
    updated_by=v_user,updated_at=now()
  where id=p_authorisation_id;
  insert into public.scheme_authorisation_event(authorisation_id,event_type,actor_user_id,metadata)
  values(p_authorisation_id,'status_changed',v_user,jsonb_build_object('from_status',v_auth.status,'to_status',p_status,'authorisation_number',p_authorisation_number));
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(v_auth.practice_id,v_auth.patient_id,'scheme_authorisation_status',now(),'Medical scheme authorisation '||replace(p_status,'_',' '),coalesce(p_authorisation_number,v_auth.request_reference,'Authorisation'),'scheme_authorisation',p_authorisation_id,v_user,'PracticeCtrl',jsonb_build_object('from_status',v_auth.status,'to_status',p_status));
  return p_authorisation_id;
end;
$$;
