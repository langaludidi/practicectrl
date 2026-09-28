
create or replace function public.promote_patient_intake_documents(p_intake_id uuid,p_patient_id uuid)
returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid()); s public.patient_intake_session%rowtype; d record; v_doc uuid; n integer:=0;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required'; end if;
 select * into s from public.patient_intake_session where id=p_intake_id for update;
 if not found then raise exception 'Patient intake not found'; end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=s.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')) then raise exception 'Patient intake review role required'; end if;
 if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=s.practice_id) then raise exception 'Patient not found in selected practice'; end if;
 for d in select * from public.patient_intake_document where intake_session_id=p_intake_id and verification_status='verified' and promoted_document_id is null order by uploaded_at loop
   v_doc:=gen_random_uuid();
   insert into public.patient_document(id,practice_id,patient_id,document_type,title,clinical_data,status,content_json,storage_bucket,storage_path,mime_type,byte_size,sha256,created_by,generated_at)
   values(v_doc,s.practice_id,p_patient_id,d.document_type,d.original_filename,false,'generated',jsonb_build_object('source','patient_intake','intake_session_id',p_intake_id,'intake_document_id',d.id,'verified_at',d.verified_at),d.storage_bucket,d.storage_path,d.mime_type,d.file_size_bytes,d.sha256,v_user,now());
   update public.patient_intake_document set promoted_document_id=v_doc where id=d.id;
   insert into public.patient_document_event(document_id,event_type,actor_user_id,metadata) values(v_doc,'created',v_user,jsonb_build_object('source','patient_intake','intake_session_id',p_intake_id));
   n:=n+1;
 end loop;
 return n;
end $$;

create or replace function public.resolve_scheme_membership_verification(
  p_case_id uuid,
  p_outcome text,
  p_external_reference text default null,
  p_evidence_document_id uuid default null,
  p_effective_from date default null,
  p_effective_to date default null,
  p_notes text default null
) returns uuid
language plpgsql security invoker set search_path=public,pg_temp as $$
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
  if not exists(select 1 from public.practice_staff_member s where s.user_id=v_user and s.practice_id=c.practice_id and s.active and s.role in ('reception','billing','practice_manager','clinical_admin','system_admin')) then raise exception 'Membership verification role required'; end if;

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

  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system,metadata)
  values(c.practice_id,c.patient_id,'scheme_membership_verification_resolved',now(),'Medical-scheme membership verification '||replace(p_outcome,'_',' '),
    case when v_ref is not null then 'Reference recorded' else 'Evidence recorded' end,
    'scheme_membership_verification_case',c.id,v_user,'PracticeCtrl',
    jsonb_build_object('membership_id',m.id,'outcome',p_outcome,'verification_method',c.verification_method,'evidence_document_id',p_evidence_document_id));
  return m.id;
end $$;

