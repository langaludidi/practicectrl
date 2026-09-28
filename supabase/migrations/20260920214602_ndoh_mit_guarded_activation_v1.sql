
begin;

alter table public.coding_source_release
  add column if not exists source_dataset_release_id uuid
    references public.source_dataset_release(id) on delete restrict;

create unique index if not exists coding_source_release_dataset_release_uq
  on public.coding_source_release(source_dataset_release_id)
  where source_dataset_release_id is not null;

create unique index if not exists one_active_source_dataset_release_idx
  on public.source_dataset_release(dataset_id)
  where status='active';

create or replace function public.activate_ndoh_mit_release(
  p_coding_release_id uuid,
  p_dataset_release_id uuid,
  p_actor_user_id uuid
)
returns void
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_dataset_release public.source_dataset_release%rowtype;
  v_source_file public.source_file%rowtype;
  v_coding_release public.coding_source_release%rowtype;
  v_code_count bigint;
begin
  select * into v_dataset_release
  from public.source_dataset_release
  where id=p_dataset_release_id
  for update;

  if not found then raise exception 'Dataset release not found'; end if;
  if v_dataset_release.status <> 'pending_review' then
    raise exception 'Dataset release must be pending_review before activation';
  end if;
  if v_dataset_release.content_sha256 is null or v_dataset_release.source_file_id is null then
    raise exception 'Dataset release has no governed source file/hash';
  end if;

  select * into v_source_file
  from public.source_file
  where id=v_dataset_release.source_file_id
  for update;

  if not found then raise exception 'Governed source file not found'; end if;
  if v_source_file.status <> 'validated' then
    raise exception 'Governed source file must be validated before activation';
  end if;
  if v_source_file.sha256 <> v_dataset_release.content_sha256 then
    raise exception 'Governed source-file hash does not match dataset release';
  end if;

  select * into v_coding_release
  from public.coding_source_release
  where id=p_coding_release_id
  for update;

  if not found then raise exception 'Coding source release not found'; end if;
  if v_coding_release.authority <> 'NDOH' or v_coding_release.source_name <> 'ICD-10 Master Industry Table' then
    raise exception 'Coding release is not an NDoH MIT release';
  end if;
  if v_coding_release.status <> 'pending_review' then
    raise exception 'Coding source release must be pending_review before activation';
  end if;
  if v_coding_release.source_dataset_release_id <> p_dataset_release_id then
    raise exception 'Coding release is not linked to the supplied governed dataset release';
  end if;
  if v_coding_release.source_file_hash <> v_source_file.sha256 then
    raise exception 'Coding release hash does not match the governed source file';
  end if;

  select count(*) into v_code_count
  from public.sa_icd10_code
  where source_release_id=p_coding_release_id;

  if v_code_count < 1 then
    raise exception 'No canonical ICD-10 rows have been loaded for this release';
  end if;

  update public.coding_source_release
  set status='superseded'
  where authority='NDOH'
    and source_name='ICD-10 Master Industry Table'
    and status='active'
    and id<>p_coding_release_id;

  update public.source_dataset_release
  set status='superseded'
  where dataset_id=v_dataset_release.dataset_id
    and status='active'
    and id<>p_dataset_release_id;

  update public.source_dataset_release
  set status='active',
      activated_by=p_actor_user_id,
      activated_at=now()
  where id=p_dataset_release_id;

  update public.coding_source_release
  set status='active',
      activated_by=p_actor_user_id,
      activated_at=now()
  where id=p_coding_release_id;

  update public.source_file
  set status='registered',
      source_release_id=p_dataset_release_id
  where id=v_source_file.id;

  insert into public.coding_audit_event(
    practice_id,actor_user_id,actor_role,event_type,entity_type,entity_id,
    source_release_ids,metadata
  )
  values(
    null,p_actor_user_id,'system_admin','SOURCE_RELEASE_ACTIVATED',
    'coding_source_release',p_coding_release_id,
    jsonb_build_object(
      'coding_source_release_id',p_coding_release_id,
      'source_dataset_release_id',p_dataset_release_id
    ),
    jsonb_build_object(
      'sha256',v_source_file.sha256,
      'code_count',v_code_count
    )
  );
end;
$$;

revoke all on function public.activate_ndoh_mit_release(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.activate_ndoh_mit_release(uuid,uuid,uuid)
  to service_role;

commit;
