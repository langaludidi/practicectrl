
create or replace function public.create_source_dataset_release_draft(
  p_dataset_id uuid,
  p_release_name text,
  p_version text default null,
  p_published_date date default null,
  p_effective_from date default null,
  p_effective_to date default null,
  p_source_uri text default null,
  p_licence_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_practice uuid;
  v_dataset public.source_dataset%rowtype;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then
    raise exception 'MFA assurance level 2 required';
  end if;

  select practice_id into v_practice
  from public.practice_staff_member
  where user_id=v_user and active and role='system_admin'
  limit 1;
  if v_practice is null then raise exception 'System administrator role required'; end if;

  select * into v_dataset from public.source_dataset where id=p_dataset_id;
  if not found then raise exception 'Governed dataset not found'; end if;

  if length(trim(coalesce(p_release_name,'')))<2 then
    raise exception 'Release name is required';
  end if;
  if p_effective_to is not null and p_effective_from is not null and p_effective_to<p_effective_from then
    raise exception 'Effective-to date cannot precede effective-from date';
  end if;
  if v_dataset.licence_required and length(trim(coalesce(p_licence_reference,'')))<3 then
    raise exception 'Licensed dataset releases require a licence reference';
  end if;

  if exists(
    select 1 from public.source_dataset_release r
    where r.dataset_id=p_dataset_id
      and lower(r.release_name)=lower(trim(p_release_name))
      and coalesce(r.version,'')=coalesce(nullif(trim(coalesce(p_version,'')),''),'')
      and r.status in ('pending_review','active')
  ) then
    raise exception 'A pending or active release with the same name/version already exists';
  end if;

  insert into public.source_dataset_release(
    dataset_id,release_name,version,published_date,effective_from,effective_to,
    retrieved_at,source_uri,content_sha256,licence_reference,status,imported_by,notes
  ) values(
    p_dataset_id,trim(p_release_name),nullif(trim(coalesce(p_version,'')),''),
    p_published_date,p_effective_from,p_effective_to,now(),
    nullif(trim(coalesce(p_source_uri,'')),''),
    null,nullif(trim(coalesce(p_licence_reference,'')),''),
    'pending_review',v_user,nullif(trim(coalesce(p_notes,'')),'')
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_source_dataset_release_draft(uuid,text,text,date,date,date,text,text,text)
from public,anon;
grant execute on function public.create_source_dataset_release_draft(uuid,text,text,date,date,date,text,text,text)
to authenticated;

