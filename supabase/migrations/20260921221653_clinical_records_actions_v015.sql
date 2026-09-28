create or replace function public.save_clinical_note(
  p_note_id uuid,
  p_encounter_id uuid,
  p_note_type text,
  p_title text,
  p_subjective text,
  p_objective text,
  p_assessment text,
  p_plan text,
  p_narrative text
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_enc public.practice_encounter%rowtype;
  v_note public.clinical_note%rowtype;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_note_type not in ('consultation','progress','procedure','telephone','review','other') then raise exception 'Invalid clinical note type'; end if;
  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then raise exception 'Encounter not found or not accessible'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_enc.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then raise exception 'Clinical role required'; end if;
  if p_note_id is null then
    insert into public.clinical_note(practice_id,patient_id,encounter_id,note_type,title,subjective,objective,assessment,plan,narrative,author_user_id)
    values(v_enc.practice_id,v_enc.patient_id,v_enc.id,p_note_type,nullif(trim(coalesce(p_title,'')),''),nullif(trim(coalesce(p_subjective,'')),''),nullif(trim(coalesce(p_objective,'')),''),nullif(trim(coalesce(p_assessment,'')),''),nullif(trim(coalesce(p_plan,'')),''),nullif(trim(coalesce(p_narrative,'')),''),v_user)
    returning id into v_id;
    insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata) values(v_id,'created',v_user,jsonb_build_object('note_type',p_note_type));
    return v_id;
  end if;
  select * into v_note from public.clinical_note where id=p_note_id for update;
  if not found or v_note.encounter_id<>p_encounter_id then raise exception 'Clinical note not found for encounter'; end if;
  if v_note.status<>'draft' then raise exception 'Only draft clinical notes can be edited'; end if;
  if v_note.author_user_id<>v_user and not exists(select 1 from public.practice_encounter e where e.id=v_note.encounter_id and e.practitioner_user_id=v_user) then raise exception 'Only the note author or encounter practitioner may edit this draft'; end if;
  update public.clinical_note set note_type=p_note_type,title=nullif(trim(coalesce(p_title,'')),''),subjective=nullif(trim(coalesce(p_subjective,'')),''),objective=nullif(trim(coalesce(p_objective,'')),''),assessment=nullif(trim(coalesce(p_assessment,'')),''),plan=nullif(trim(coalesce(p_plan,'')),''),narrative=nullif(trim(coalesce(p_narrative,'')),''),updated_at=now() where id=p_note_id;
  insert into public.clinical_note_event(note_id,event_type,actor_user_id) values(p_note_id,'updated',v_user);
  return p_note_id;
end;
$$;

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
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,source_system,source_reference)
  values(v_note.practice_id,v_note.patient_id,'clinical_note_signed',now(),'Clinical note signed',coalesce(v_note.title,initcap(replace(v_note.note_type,'_',' '))),'PracticeCtrl',p_note_id::text);
  return p_note_id;
end;
$$;

create or replace function public.create_clinical_note_amendment(p_note_id uuid) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_note public.clinical_note%rowtype;
  v_new uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_note from public.clinical_note where id=p_note_id;
  if not found or v_note.status not in ('signed','amended') then raise exception 'Only a signed clinical note can be amended'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_note.practice_id and m.active and m.role='practitioner') then raise exception 'Practitioner role required'; end if;
  insert into public.clinical_note(practice_id,patient_id,encounter_id,note_type,title,subjective,objective,assessment,plan,narrative,structured_data,amendment_of_note_id,author_user_id)
  values(v_note.practice_id,v_note.patient_id,v_note.encounter_id,v_note.note_type,v_note.title,v_note.subjective,v_note.objective,v_note.assessment,v_note.plan,v_note.narrative,v_note.structured_data,v_note.id,v_user)
  returning id into v_new;
  insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata) values(v_new,'amendment_created',v_user,jsonb_build_object('amends_note_id',v_note.id));
  return v_new;
end;
$$;

revoke all on function public.save_clinical_note(uuid,uuid,text,text,text,text,text,text,text) from public,anon;
revoke all on function public.sign_clinical_note(uuid) from public,anon;
revoke all on function public.create_clinical_note_amendment(uuid) from public,anon;
grant execute on function public.save_clinical_note(uuid,uuid,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.sign_clinical_note(uuid) to authenticated;
grant execute on function public.create_clinical_note_amendment(uuid) to authenticated;

insert into public.platform_module(module_key,display_name,descriptor,flagship,enabled_by_default,ai_enabled,voice_enabled,status)
values('clinical_records','Clinical Records','Encounter-centred clinical documentation, observations and signed record integrity',false,true,true,true,'development')
on conflict(module_key) do update set display_name=excluded.display_name,descriptor=excluded.descriptor,enabled_by_default=true,ai_enabled=true,voice_enabled=true,status='development';

insert into public.practice_module(practice_id,module_id,enabled,enabled_at,configuration)
select p.id,m.id,true,now(),'{}'::jsonb from public.practice p join public.platform_module m on m.module_key='clinical_records'
on conflict(practice_id,module_id) do update set enabled=true,enabled_at=coalesce(public.practice_module.enabled_at,excluded.enabled_at);

create trigger tenant_guard_clinical_note_patient before insert or update of practice_id,patient_id on public.clinical_note for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger tenant_guard_clinical_note_encounter before insert or update of practice_id,encounter_id on public.clinical_note for each row execute function public.enforce_same_practice_reference('practice_encounter','encounter_id');
create trigger tenant_guard_clinical_note_diagnosis_note before insert or update of practice_id,note_id on public.clinical_note_diagnosis for each row execute function public.enforce_same_practice_reference('clinical_note','note_id');
create trigger tenant_guard_clinical_observation_patient before insert or update of practice_id,patient_id on public.clinical_observation for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger tenant_guard_clinical_observation_encounter before insert or update of practice_id,encounter_id on public.clinical_observation for each row execute function public.enforce_same_practice_reference('practice_encounter','encounter_id');
