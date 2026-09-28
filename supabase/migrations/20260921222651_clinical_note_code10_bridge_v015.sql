create or replace function public.attach_clinical_note_diagnosis(
  p_note_id uuid,
  p_coding_decision_id uuid
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_note public.clinical_note%rowtype;
  v_dec public.coding_decision%rowtype;
  v_session public.coding_session%rowtype;
  v_code public.sa_icd10_code%rowtype;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_note from public.clinical_note where id=p_note_id;
  if not found or v_note.status<>'draft' then raise exception 'A draft clinical note is required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_note.practice_id and m.active and m.role in ('practitioner','clinical_admin')) then raise exception 'Clinical role required'; end if;

  select * into v_dec from public.coding_decision where id=p_coding_decision_id and practice_id=v_note.practice_id;
  if not found or v_dec.decision not in ('ACCEPTED','MANUALLY_SELECTED') then raise exception 'An accepted Code10 decision is required'; end if;
  select * into v_session from public.coding_session where id=v_dec.coding_session_id;
  if not found or v_session.encounter_id is distinct from v_note.encounter_id then raise exception 'Code10 decision does not belong to this encounter'; end if;
  select * into v_code from public.sa_icd10_code where id=v_dec.code_id;
  if not found then raise exception 'ICD-10 code reference not found'; end if;

  insert into public.clinical_note_diagnosis(practice_id,note_id,coding_decision_id,code_system,code,normalized_code,description_snapshot,position,source,created_by)
  values(v_note.practice_id,v_note.id,v_dec.id,'ICD-10',v_code.code,v_code.normalized_code,v_code.official_description,v_dec.position,'Code10',v_user)
  on conflict(note_id,normalized_code,position) do update
    set coding_decision_id=excluded.coding_decision_id,description_snapshot=excluded.description_snapshot,source='Code10'
  returning id into v_id;

  insert into public.clinical_note_event(note_id,event_type,actor_user_id,metadata)
  values(v_note.id,'diagnosis_attached',v_user,jsonb_build_object('coding_decision_id',v_dec.id,'code',v_code.code,'position',v_dec.position));

  return v_id;
end;
$$;

revoke all on function public.attach_clinical_note_diagnosis(uuid,uuid) from public,anon;
grant execute on function public.attach_clinical_note_diagnosis(uuid,uuid) to authenticated;
