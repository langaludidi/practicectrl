
create or replace function public.guard_source_file_governance()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_licence_required boolean;
  v_release_dataset uuid;
  v_release_status text;
  v_licence_reference text;
begin
  select licence_required
    into v_licence_required
  from public.source_dataset
  where id = new.dataset_id;

  if not found then
    raise exception 'Governed dataset not found for source file';
  end if;

  if tg_op = 'UPDATE' then
    if new.dataset_id is distinct from old.dataset_id
       or new.source_release_id is distinct from old.source_release_id
       or new.bucket_id is distinct from old.bucket_id
       or new.object_path is distinct from old.object_path
       or new.original_filename is distinct from old.original_filename
       or new.mime_type is distinct from old.mime_type
       or new.byte_size is distinct from old.byte_size
       or new.sha256 is distinct from old.sha256
       or new.uploaded_by is distinct from old.uploaded_by
       or new.uploaded_at is distinct from old.uploaded_at
       or new.source_uri is distinct from old.source_uri then
      raise exception 'Source-file provenance is immutable after registration';
    end if;
  end if;

  if new.bucket_id <> 'governed-source-files' then
    raise exception 'Governed source files must use governed-source-files bucket';
  end if;

  if new.source_release_id is not null then
    select r.dataset_id, r.status, r.licence_reference
      into v_release_dataset, v_release_status, v_licence_reference
    from public.source_dataset_release r
    where r.id = new.source_release_id;

    if not found then
      raise exception 'Referenced governed release does not exist';
    end if;

    if v_release_dataset <> new.dataset_id then
      raise exception 'Source file and governed release must belong to the same dataset';
    end if;

    if tg_op = 'INSERT' and v_release_status <> 'pending_review' then
      raise exception 'New source files may only attach to pending-review releases';
    end if;
  end if;

  if v_licence_required then
    if new.source_release_id is null then
      raise exception 'Licensed datasets require a governed release before source bytes may be registered';
    end if;

    if nullif(btrim(v_licence_reference), '') is null then
      raise exception 'Licensed datasets require a licence reference before source bytes may be registered';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_source_file_governance on public.source_file;
create trigger trg_guard_source_file_governance
before insert or update on public.source_file
for each row execute function public.guard_source_file_governance();

create or replace function public.guard_source_release_governance()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_dataset public.source_dataset%rowtype;
  v_file_dataset uuid;
  v_file_release uuid;
  v_file_hash text;
begin
  select *
    into v_dataset
  from public.source_dataset
  where id = new.dataset_id;

  if not found then
    raise exception 'Governed dataset not found for release';
  end if;

  if v_dataset.licence_required
     and nullif(btrim(new.licence_reference), '') is null then
    raise exception 'Licensed dataset releases require a licence reference';
  end if;

  if v_dataset.versioned_required
     and nullif(btrim(new.version), '') is null then
    raise exception 'This governed dataset requires an explicit release version';
  end if;

  if v_dataset.effective_dating_required
     and new.status = 'active'
     and new.effective_from is null then
    raise exception 'Active releases for this dataset require an effective-from date';
  end if;

  if new.source_file_id is not null then
    select f.dataset_id, f.source_release_id, f.sha256
      into v_file_dataset, v_file_release, v_file_hash
    from public.source_file f
    where f.id = new.source_file_id;

    if not found then
      raise exception 'Linked governed source file does not exist';
    end if;

    if v_file_dataset <> new.dataset_id then
      raise exception 'Governed release and source file must belong to the same dataset';
    end if;

    if v_file_release is distinct from new.id then
      raise exception 'Source file must be bound to this governed release';
    end if;

    if new.content_sha256 is null then
      new.content_sha256 := v_file_hash;
    elsif new.content_sha256 <> v_file_hash then
      raise exception 'Release content hash must match its governed source file';
    end if;
  end if;

  if v_dataset.provenance_required and new.status = 'active' then
    if new.source_file_id is null or nullif(btrim(new.content_sha256), '') is null then
      raise exception 'Active release requires governed source provenance';
    end if;
  end if;

  if new.status = 'active' and new.activated_at is null then
    new.activated_at := now();
  end if;

  if tg_op = 'UPDATE' then
    if old.source_file_id is not null and (
         new.source_file_id is distinct from old.source_file_id
         or new.content_sha256 is distinct from old.content_sha256
         or new.source_uri is distinct from old.source_uri
       ) then
      raise exception 'Release provenance is immutable once a governed source file is linked';
    end if;

    if old.status = 'active' and (
         new.dataset_id is distinct from old.dataset_id
         or new.release_name is distinct from old.release_name
         or new.version is distinct from old.version
         or new.published_date is distinct from old.published_date
         or new.effective_from is distinct from old.effective_from
         or new.effective_to is distinct from old.effective_to
         or new.licence_reference is distinct from old.licence_reference
         or new.source_file_id is distinct from old.source_file_id
         or new.content_sha256 is distinct from old.content_sha256
         or new.source_uri is distinct from old.source_uri
       ) then
      raise exception 'Activated governed release metadata and provenance are immutable';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_source_release_governance on public.source_dataset_release;
create trigger trg_guard_source_release_governance
before insert or update on public.source_dataset_release
for each row execute function public.guard_source_release_governance();

create unique index if not exists source_dataset_release_one_active_uq
  on public.source_dataset_release(dataset_id)
  where status = 'active';

create unique index if not exists source_dataset_release_file_uq
  on public.source_dataset_release(source_file_id)
  where source_file_id is not null;

create unique index if not exists source_dataset_release_pending_active_name_version_uq
  on public.source_dataset_release(
    dataset_id,
    lower(release_name),
    coalesce(version, '')
  )
  where status in ('pending_review','active');

