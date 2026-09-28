
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

revoke insert,update,delete on public.scheme_membership_verification_case from authenticated;
revoke update on public.crm_patient_scheme_membership from authenticated;

create or replace function private.open_scheme_membership_verification_internal(
  p_membership_id uuid,
  p_method text,
  p_notes text
) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  v_user uuid := (select auth.uid());
  m public.crm_patient_scheme_membership%rowtype;
  v_id uuid;
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'AAL2 authentication required'; end if;
  if p_method not in ('manual_evidence','scheme_portal','switch_provider','other_authoritative') then raise exception 'Invalid verification method'; end if;

  select * into m from public.crm_patient_scheme_membership where id=p_membership_id for update;
  if not found then raise exception 'Membership not found or inaccessible'; end if;
  if not exists(
    select 1 from public.practice_staff_member s
    where s.user_id=v_user and s.practice_id=m.practice_id and s.active
      and s.role in ('reception','billing','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'Membership verification role required'; end if;

  select id into v_id from public.scheme_membership_verification_case
  where membership_id=p_membership_id and status='pending' limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.scheme_membership_verification_case(
    practice_id,membership_id,patient_id,verification_method,status,notes,requested_by
  ) values(
    m.practice_id,m.id,m.patient_id,p_method,'pending',nullif(trim(coalesce(p_notes,'')),''),v_user
  ) returning id into v_id;

  update public.crm_patient_scheme_membership
  set membership_status='needs_review',verification_source=null,verified_at=null,updated_by=v_user,updated_at=now()
  where id=m.id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    m.practice_id,m.patient_id,'scheme_membership_verification_started',now(),
    'Medical-scheme membership verification started',
    'Verification method: '||replace(p_method,'_',' '),
    'scheme_membership_verification_case',v_id,v_user,'PracticeCtrl',
    jsonb_build_object('membership_id',m.id,'verification_method',p_method)
  );

  return v_id;
end $$;

create or replace function private.resolve_scheme_membership_verification_internal(
  p_case_id uuid,
  p_outcome text,
  p_external_reference text,
  p_evidence_document_id uuid,
  p_effective_from date,
  p_effective_to date,
  p_notes text
) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  v_user uuid := (select auth.uid());
  c public.scheme_membership_verification_case%rowtype;
  m public.crm_patient_scheme_membership%rowtype;
  v_ref text := nullif(trim(coalesce(p_external_reference,'')),'');
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'AAL2 authentication required'; end if;
  if p_outcome not in ('verified','inactive','failed','unavailable','cancelled') then raise exception 'Invalid verification outcome'; end if;
  if p_effective_to is not null and p_effective_from is not null and p_effective_to < p_effective_from then raise exception 'Effective end date cannot precede start date'; end if;

  select * into c from public.scheme_membership_verification_case where id=p_case_id for update;
  if not found or c.status<>'pending' then raise exception 'Open verification case not found'; end if;
  select * into m from public.crm_patient_scheme_membership where id=c.membership_id and practice_id=c.practice_id and patient_id=c.patient_id for update;
  if not found then raise exception 'Membership linked to verification case is unavailable'; end if;

  if not exists(
    select 1 from public.practice_staff_member s
    where s.user_id=v_user and s.practice_id=c.practice_id and s.active
      and s.role in ('reception','billing','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'Membership verification role required'; end if;

  if p_evidence_document_id is not null and not exists(
    select 1 from public.patient_document d
    where d.id=p_evidence_document_id and d.practice_id=c.practice_id and d.patient_id=c.patient_id
      and d.status in('generated','signed')
  ) then raise exception 'Evidence document must be a generated or signed document linked to this patient and practice'; end if;

  if p_outcome in ('verified','inactive') then
    if c.verification_method='manual_evidence' and p_evidence_document_id is null then raise exception 'Manual verification requires a patient evidence document'; end if;
    if c.verification_method<>'manual_evidence' and v_ref is null then raise exception 'Authoritative verification reference is required'; end if;
  end if;

  update public.scheme_membership_verification_case
  set status=p_outcome,external_reference=v_ref,evidence_document_id=p_evidence_document_id,
      effective_from=p_effective_from,effective_to=p_effective_to,
      notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),
      response_summary=jsonb_build_object('outcome',p_outcome,'method',c.verification_method,'evidence_document_id',p_evidence_document_id,'external_reference_present',v_ref is not null),
      resolved_by=v_user,resolved_at=now(),updated_at=now()
  where id=p_case_id;

  update public.crm_patient_scheme_membership
  set membership_status=case when p_outcome='verified' then 'active_verified' when p_outcome='inactive' then 'inactive_verified' when p_outcome in ('failed','unavailable') then 'needs_review' else 'unverified' end,
      verification_source=case when p_outcome in ('verified','inactive') then c.verification_method else null end,
      verified_at=case when p_outcome in ('verified','inactive') then now() else null end,
      effective_from=coalesce(p_effective_from,effective_from),effective_to=coalesce(p_effective_to,effective_to),
      updated_by=v_user,updated_at=now()
  where id=m.id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata
  ) values(
    c.practice_id,c.patient_id,'scheme_membership_verification_resolved',now(),
    'Medical-scheme membership verification '||replace(p_outcome,'_',' '),
    case when v_ref is not null then 'Reference recorded' else 'Evidence recorded' end,
    'scheme_membership_verification_case',c.id,v_user,'PracticeCtrl',
    jsonb_build_object('membership_id',m.id,'outcome',p_outcome,'verification_method',c.verification_method,'evidence_document_id',p_evidence_document_id)
  );

  return m.id;
end $$;

revoke all on function private.open_scheme_membership_verification_internal(uuid,text,text) from public,anon;
revoke all on function private.resolve_scheme_membership_verification_internal(uuid,text,text,uuid,date,date,text) from public,anon;
grant execute on function private.open_scheme_membership_verification_internal(uuid,text,text) to authenticated;
grant execute on function private.resolve_scheme_membership_verification_internal(uuid,text,text,uuid,date,date,text) to authenticated;

create or replace function public.open_scheme_membership_verification(
  p_membership_id uuid,
  p_method text default 'manual_evidence',
  p_notes text default null
) returns uuid
language sql security invoker set search_path='' as $$
  select private.open_scheme_membership_verification_internal(p_membership_id,p_method,p_notes)
$$;

create or replace function public.resolve_scheme_membership_verification(
  p_case_id uuid,
  p_outcome text,
  p_external_reference text default null,
  p_evidence_document_id uuid default null,
  p_effective_from date default null,
  p_effective_to date default null,
  p_notes text default null
) returns uuid
language sql security invoker set search_path='' as $$
  select private.resolve_scheme_membership_verification_internal(p_case_id,p_outcome,p_external_reference,p_evidence_document_id,p_effective_from,p_effective_to,p_notes)
$$;

revoke all on function public.open_scheme_membership_verification(uuid,text,text) from public,anon;
revoke all on function public.resolve_scheme_membership_verification(uuid,text,text,uuid,date,date,text) from public,anon;
grant execute on function public.open_scheme_membership_verification(uuid,text,text) to authenticated;
grant execute on function public.resolve_scheme_membership_verification(uuid,text,text,uuid,date,date,text) to authenticated;

