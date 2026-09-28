
begin;

create table if not exists public.source_file (
  id uuid primary key default gen_random_uuid(),
  dataset_id uuid not null references public.source_dataset(id) on delete restrict,
  source_release_id uuid references public.source_dataset_release(id) on delete restrict,
  bucket_id text not null default 'governed-source-files',
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
  source_uri text,
  constraint source_file_object_unique unique(bucket_id,object_path),
  constraint source_file_dataset_hash_unique unique(dataset_id,sha256),
  constraint source_file_registered_ck check (
    status <> 'registered' or source_release_id is not null
  )
);

create index if not exists source_file_dataset_status_idx
  on public.source_file(dataset_id,status,uploaded_at desc);
create index if not exists source_file_release_idx
  on public.source_file(source_release_id)
  where source_release_id is not null;
create index if not exists source_file_uploaded_by_idx
  on public.source_file(uploaded_by);

alter table public.source_dataset_release
  add column if not exists source_file_id uuid references public.source_file(id) on delete restrict,
  add column if not exists validation_summary jsonb;

create unique index if not exists source_dataset_release_source_file_uq
  on public.source_dataset_release(source_file_id)
  where source_file_id is not null;

create table if not exists public.source_import_batch (
  id uuid primary key default gen_random_uuid(),
  dataset_id uuid not null references public.source_dataset(id) on delete restrict,
  source_file_id uuid not null references public.source_file(id) on delete restrict,
  source_release_id uuid references public.source_dataset_release(id) on delete restrict,
  parser_version text not null,
  status text not null default 'staging'
    check (status in ('staging','validated','reviewed','promoted','failed')),
  records_received integer not null default 0,
  records_valid integer not null default 0,
  records_rejected integer not null default 0,
  validation_summary jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  promoted_by uuid references auth.users(id) on delete set null
);

create index if not exists source_import_batch_dataset_idx
  on public.source_import_batch(dataset_id,status,started_at desc);
create index if not exists source_import_batch_file_idx
  on public.source_import_batch(source_file_id);
create index if not exists source_import_batch_release_idx
  on public.source_import_batch(source_release_id)
  where source_release_id is not null;

create table if not exists public.medical_scheme_import_staging (
  import_batch_id uuid not null references public.source_import_batch(id) on delete cascade,
  row_number integer not null,
  cms_registration_number text,
  scheme_name text,
  scheme_type text check (scheme_type is null or scheme_type in ('open','restricted','other')),
  parse_status text not null default 'valid'
    check (parse_status in ('valid','invalid')),
  parse_error text,
  raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.medical_scheme_option_import_staging (
  import_batch_id uuid not null references public.source_import_batch(id) on delete cascade,
  row_number integer not null,
  cms_registration_number text,
  scheme_name text,
  option_name text,
  approval_status text
    check (approval_status is null or approval_status in ('approved','conditional','discontinued','pending','unknown')),
  comments text,
  parse_status text not null default 'valid'
    check (parse_status in ('valid','invalid')),
  parse_error text,
  raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

alter table public.source_file enable row level security;
alter table public.source_import_batch enable row level security;
alter table public.medical_scheme_import_staging enable row level security;
alter table public.medical_scheme_option_import_staging enable row level security;

revoke all on table public.source_file from anon,authenticated;
revoke all on table public.source_import_batch from anon,authenticated;
revoke all on table public.medical_scheme_import_staging from anon,authenticated;
revoke all on table public.medical_scheme_option_import_staging from anon,authenticated;

grant select,insert on table public.source_file to authenticated;
grant update (status,validation_summary,source_release_id)
  on table public.source_file to authenticated;

drop policy if exists source_file_system_admin_read on public.source_file;
create policy source_file_system_admin_read
on public.source_file for select to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active and m.role='system_admin'
  )
);

drop policy if exists source_file_system_admin_insert on public.source_file;
create policy source_file_system_admin_insert
on public.source_file for insert to authenticated
with check (
  uploaded_by=(select auth.uid())
  and bucket_id='governed-source-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active and m.role='system_admin'
  )
);

drop policy if exists source_file_system_admin_update on public.source_file;
create policy source_file_system_admin_update
on public.source_file for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active and m.role='system_admin'
  )
)
with check (
  bucket_id='governed-source-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active and m.role='system_admin'
  )
);

insert into storage.buckets(
  id,name,public,file_size_limit,allowed_mime_types,versioning_status
)
values(
  'governed-source-files','governed-source-files',false,52428800,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
    'text/csv',
    'application/csv',
    'application/xml',
    'text/xml',
    'application/json',
    'text/plain',
    'application/octet-stream'
  ],
  'DISABLED'
)
on conflict(id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists governed_source_files_admin_select on storage.objects;
create policy governed_source_files_admin_select
on storage.objects for select to authenticated
using (
  bucket_id='governed-source-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active and m.role='system_admin'
  )
);

drop policy if exists governed_source_files_admin_insert on storage.objects;
create policy governed_source_files_admin_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='governed-source-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active and m.role='system_admin'
  )
);

-- No authenticated UPDATE/DELETE policy: source binaries are immutable.

update public.source_dataset_release r
set source_uri='https://www.health.gov.za/wp-content/uploads/2021/04/ICD-10_MIT_2021_Excel_16-March_2021.xlsx'
from public.source_dataset d
where r.dataset_id=d.id
  and d.dataset_key='sa_icd10_mit'
  and r.release_name='South African ICD-10 Master Industry Table 2021';

update public.source_dataset_release r
set source_uri='https://www.medicalschemes.co.za/download/3819/2026-circulars-current/31038/circular-12-of-2026.pdf'
from public.source_dataset d
where r.dataset_id=d.id
  and d.dataset_key='cms_schemes_2026'
  and r.release_name='Registered medical schemes - 2026';

update public.source_dataset_release r
set source_uri='https://www.medicalschemes.co.za/download/3770/2025-circulars-current/30624/circular-41-of-2025_-list-for-2026-open-and-restricted-schemes.pdf'
from public.source_dataset d
where r.dataset_id=d.id
  and d.dataset_key='cms_benefit_options_2026'
  and r.release_name='Approved benefit options - 2026';

commit;
