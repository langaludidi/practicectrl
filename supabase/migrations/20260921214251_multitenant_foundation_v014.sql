alter table public.practice
  add column if not exists tenant_slug text,
  add column if not exists legal_name text,
  add column if not exists country_code text not null default 'ZA',
  add column if not exists timezone text not null default 'Africa/Johannesburg',
  add column if not exists settings jsonb not null default '{}'::jsonb,
  add column if not exists branding jsonb not null default '{}'::jsonb;

update public.practice
set tenant_slug = case
  when id='a51cb8af-d3a9-4663-b0b6-0f35738a31dc'::uuid then 'dr-tembisa-tini-inc'
  else trim(both '-' from regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g')) || '-' || substr(id::text,1,8)
end
where tenant_slug is null;

alter table public.practice alter column tenant_slug set not null;

do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='public.practice'::regclass and conname='practice_tenant_slug_ck') then
    alter table public.practice add constraint practice_tenant_slug_ck
      check (tenant_slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');
  end if;
end $$;

create unique index if not exists practice_tenant_slug_uq on public.practice(tenant_slug);

create table if not exists public.platform_operator (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('platform_owner','platform_admin','support_auditor')),
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.platform_operator enable row level security;
revoke all on table public.platform_operator from anon, authenticated;
grant select on table public.platform_operator to authenticated;
drop policy if exists platform_operator_self_read on public.platform_operator;
create policy platform_operator_self_read on public.platform_operator
for select to authenticated
using (user_id=(select auth.uid()) and active);

create table if not exists public.user_practice_preference (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_practice_id uuid not null references public.practice(id) on delete cascade,
  updated_at timestamptz not null default now()
);
alter table public.user_practice_preference enable row level security;
revoke all on table public.user_practice_preference from anon, authenticated;
grant select,insert,update on table public.user_practice_preference to authenticated;
drop policy if exists user_practice_preference_self_read on public.user_practice_preference;
drop policy if exists user_practice_preference_self_insert on public.user_practice_preference;
drop policy if exists user_practice_preference_self_update on public.user_practice_preference;
create policy user_practice_preference_self_read on public.user_practice_preference
for select to authenticated
using (user_id=(select auth.uid()));
create policy user_practice_preference_self_insert on public.user_practice_preference
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=user_practice_preference.last_practice_id
      and m.active
  )
);
create policy user_practice_preference_self_update on public.user_practice_preference
for update to authenticated
using (user_id=(select auth.uid()))
with check (
  user_id=(select auth.uid())
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=user_practice_preference.last_practice_id
      and m.active
  )
);

create table if not exists public.platform_tenant_event (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid references public.practice(id) on delete set null,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.platform_tenant_event enable row level security;
revoke all on table public.platform_tenant_event from anon, authenticated;
grant select on table public.platform_tenant_event to authenticated;
drop policy if exists platform_tenant_event_operator_read on public.platform_tenant_event;
create policy platform_tenant_event_operator_read on public.platform_tenant_event
for select to authenticated
using (
  exists(
    select 1 from public.platform_operator po
    where po.user_id=(select auth.uid()) and po.active
  )
);

drop policy if exists practice_platform_operator_read on public.practice;
create policy practice_platform_operator_read on public.practice
for select to authenticated
using (
  exists(
    select 1 from public.platform_operator po
    where po.user_id=(select auth.uid()) and po.active
  )
);

drop policy if exists source_file_system_admin_read on public.source_file;
drop policy if exists source_file_platform_operator_read on public.source_file;
create policy source_file_platform_operator_read on public.source_file
for select to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(
    select 1 from public.platform_operator po
    where po.user_id=(select auth.uid()) and po.active
      and po.role in ('platform_owner','platform_admin','support_auditor')
  )
);

drop policy if exists coding_source_file_admin_select on public.coding_source_file;
drop policy if exists coding_source_file_admin_insert on public.coding_source_file;
drop policy if exists coding_source_file_admin_update on public.coding_source_file;
drop policy if exists coding_source_file_platform_operator_read on public.coding_source_file;
create policy coding_source_file_platform_operator_read on public.coding_source_file
for select to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(
    select 1 from public.platform_operator po
    where po.user_id=(select auth.uid()) and po.active
  )
);

drop policy if exists coding_source_files_admin_select on storage.objects;
drop policy if exists coding_source_files_admin_insert on storage.objects;
drop policy if exists governed_source_files_admin_select on storage.objects;
drop policy if exists coding_source_files_platform_operator_select on storage.objects;
drop policy if exists governed_source_files_platform_operator_select on storage.objects;
create policy coding_source_files_platform_operator_select on storage.objects
for select to authenticated
using (
  bucket_id='coding-source-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(
    select 1 from public.platform_operator po
    where po.user_id=(select auth.uid()) and po.active
  )
);
create policy governed_source_files_platform_operator_select on storage.objects
for select to authenticated
using (
  bucket_id='governed-source-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(
    select 1 from public.platform_operator po
    where po.user_id=(select auth.uid()) and po.active
  )
);

create or replace function public.enforce_same_practice_reference()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_fk_text text;
  v_parent_practice uuid;
begin
  if tg_nargs <> 2 then
    raise exception 'Tenant reference guard is misconfigured';
  end if;
  v_fk_text := to_jsonb(new)->>tg_argv[1];
  if v_fk_text is null or btrim(v_fk_text)='' then
    return new;
  end if;
  execute format('select practice_id from public.%I where id=$1',tg_argv[0])
    into v_parent_practice using v_fk_text::uuid;
  if v_parent_practice is not null and v_parent_practice is distinct from new.practice_id then
    raise exception 'Cross-practice reference blocked: %.% points to %',
      tg_table_name,tg_argv[1],tg_argv[0]
      using errcode='23514';
  end if;
  return new;
end;
$$;

do $$
declare
  r record;
  v_trigger text;
begin
  for r in
    with fks as (
      select child.relname child_table,parent.relname parent_table,ca.attname child_col
      from pg_constraint con
      join pg_class child on child.oid=con.conrelid
      join pg_namespace nc on nc.oid=child.relnamespace and nc.nspname='public'
      join pg_class parent on parent.oid=con.confrelid
      join pg_namespace np on np.oid=parent.relnamespace and np.nspname='public'
      join unnest(con.conkey,con.confkey) with ordinality x(cattnum,pattnum,ord) on true
      join pg_attribute ca on ca.attrelid=child.oid and ca.attnum=x.cattnum
      join pg_attribute pa on pa.attrelid=parent.oid and pa.attnum=x.pattnum
      where con.contype='f'
        and array_length(con.conkey,1)=1
        and pa.attname='id'
        and exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=child.relname and c.column_name='practice_id')
        and exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name=parent.relname and c.column_name='practice_id')
    )
    select distinct * from fks
  loop
    v_trigger := left('tenant_guard_'||r.child_table||'_'||r.child_col,63);
    execute format('drop trigger if exists %I on public.%I',v_trigger,r.child_table);
    execute format(
      'create trigger %I before insert or update of practice_id,%I on public.%I for each row execute function public.enforce_same_practice_reference(%L,%L)',
      v_trigger,r.child_col,r.child_table,r.parent_table,r.child_col
    );
  end loop;
end $$;
