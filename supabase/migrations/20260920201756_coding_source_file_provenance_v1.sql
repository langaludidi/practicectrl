
begin;

create table if not exists public.coding_source_file (
  id uuid primary key default gen_random_uuid(),
  authority public.coding_source_authority not null,
  bucket_id text not null default 'coding-source-files',
  object_path text not null,
  original_filename text not null,
  mime_type text,
  byte_size bigint not null check (byte_size > 0),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  status text not null default 'uploaded'
    check (status in ('uploaded','validated','registered','rejected')),
  validation_summary jsonb,
  source_release_id uuid references public.coding_source_release(id) on delete restrict,
  constraint coding_source_file_object_unique unique (bucket_id, object_path),
  constraint coding_source_file_hash_unique unique (authority, sha256),
  constraint coding_source_file_registered_ck check (
    status <> 'registered' or source_release_id is not null
  )
);

create index if not exists coding_source_file_uploaded_by_idx
  on public.coding_source_file(uploaded_by);
create index if not exists coding_source_file_release_idx
  on public.coding_source_file(source_release_id)
  where source_release_id is not null;
create index if not exists coding_source_file_status_idx
  on public.coding_source_file(status, uploaded_at desc);

alter table public.coding_source_file enable row level security;

revoke all on table public.coding_source_file from anon, authenticated;
grant select, insert on table public.coding_source_file to authenticated;
grant update (status, validation_summary, source_release_id)
  on table public.coding_source_file to authenticated;

drop policy if exists coding_source_file_admin_select on public.coding_source_file;
create policy coding_source_file_admin_select
on public.coding_source_file
for select
to authenticated
using (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

drop policy if exists coding_source_file_admin_insert on public.coding_source_file;
create policy coding_source_file_admin_insert
on public.coding_source_file
for insert
to authenticated
with check (
  uploaded_by = (select auth.uid())
  and bucket_id = 'coding-source-files'
  and (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

drop policy if exists coding_source_file_admin_update on public.coding_source_file;
create policy coding_source_file_admin_update
on public.coding_source_file
for update
to authenticated
using (
  (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
)
with check (
  bucket_id = 'coding-source-files'
  and (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

commit;
