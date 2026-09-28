-- South African Clinical Coding Intelligence Engine — Phase 1 schema
-- Integration SQL, not a Supabase migration file.
-- Create the actual migration in the target repository with:
--   supabase migration new clinical_coding_phase1
-- then paste/review this SQL into that generated file and test locally before db push.

begin;

create extension if not exists pg_trgm;

do $$ begin
  create type public.coding_source_authority as enum ('NDOH','CMS','PHISC','WHO','HPCSA','SERVIER','OTHER');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.coding_source_status as enum ('pending_review','active','superseded','archived');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.coding_gender_rule as enum ('M','F','U');
exception when duplicate_object then null; end $$;

create table if not exists public.coding_source_release (
  id uuid primary key default gen_random_uuid(),
  authority public.coding_source_authority not null,
  source_name text not null,
  release_name text not null,
  version text,
  published_date date,
  effective_from date,
  effective_to date,
  retrieved_at timestamptz not null default now(),
  source_uri text not null,
  source_file_hash text not null,
  licence_type text,
  licence_reference text,
  status public.coding_source_status not null default 'pending_review',
  imported_by uuid references auth.users(id) on delete set null,
  activated_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  constraint coding_source_release_hash_unique unique (authority, source_file_hash),
  constraint coding_source_release_dates_ck check (effective_to is null or effective_from is null or effective_to >= effective_from)
);

create unique index if not exists coding_one_active_ndoh_mit_idx
  on public.coding_source_release ((authority), (source_name))
  where status = 'active' and authority = 'NDOH' and source_name = 'ICD-10 Master Industry Table';

create table if not exists public.sa_icd10_code (
  id uuid primary key default gen_random_uuid(),
  source_release_id uuid not null references public.coding_source_release(id) on delete restrict,
  mit_number text,
  chapter_no text,
  chapter_desc text,
  group_code text,
  group_desc text,
  icd10_3_code text,
  icd10_3_code_desc text,
  code text not null,
  normalized_code text not null,
  official_description text not null,
  valid_clinical_use boolean not null,
  valid_primary boolean not null,
  valid_asterisk boolean not null default false,
  valid_dagger boolean not null default false,
  valid_sequelae boolean not null default false,
  age_range text,
  gender public.coding_gender_rule,
  sa_status text,
  who_start_date date,
  who_end_date date,
  who_revision_history text,
  sa_start_date date,
  sa_end_date date,
  sa_revision_history text,
  official_comment text,
  imported_at timestamptz not null default now(),
  constraint sa_icd10_code_release_code_unique unique (source_release_id, code),
  constraint sa_icd10_code_normalized_not_blank check (length(trim(normalized_code)) > 0)
);

create index if not exists sa_icd10_release_idx on public.sa_icd10_code(source_release_id);
create index if not exists sa_icd10_normalized_code_idx on public.sa_icd10_code(normalized_code);
create index if not exists sa_icd10_normalized_code_trgm_idx on public.sa_icd10_code using gin (normalized_code gin_trgm_ops);
create index if not exists sa_icd10_description_trgm_idx on public.sa_icd10_code using gin (official_description gin_trgm_ops);
create index if not exists sa_icd10_description_fts_idx on public.sa_icd10_code using gin (to_tsvector('simple', coalesce(official_description,'')));

create table if not exists public.icd10_search_alias (
  id uuid primary key default gen_random_uuid(),
  icd10_code_id uuid not null references public.sa_icd10_code(id) on delete cascade,
  alias text not null,
  alias_normalized text not null,
  alias_type text not null check (alias_type in ('common_name','abbreviation','historic_term','spelling_variant','clinical_phrase','lay_term')),
  review_status text not null default 'approved' check (review_status in ('draft','approved','retired')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint icd10_search_alias_unique unique (icd10_code_id, alias_normalized)
);
create index if not exists icd10_alias_trgm_idx on public.icd10_search_alias using gin(alias_normalized gin_trgm_ops);

create table if not exists public.sa_icd10_import_staging (
  import_batch_id uuid not null,
  row_number integer not null,
  raw_row jsonb not null,
  parse_status text not null default 'pending' check (parse_status in ('pending','valid','invalid')),
  parse_error text,
  created_at timestamptz not null default now(),
  primary key (import_batch_id, row_number)
);

create table if not exists public.coding_ingestion_job (
  id uuid primary key default gen_random_uuid(),
  source_release_id uuid not null references public.coding_source_release(id) on delete restrict,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  records_received integer not null default 0,
  records_valid integer not null default 0,
  records_rejected integer not null default 0,
  comparison_summary jsonb,
  reviewed_by uuid references auth.users(id) on delete set null,
  activated_by uuid references auth.users(id) on delete set null,
  status text not null default 'staging' check (status in ('staging','validated','reviewed','activated','failed')),
  error_log jsonb
);

create table if not exists public.coding_audit_event (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text,
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  source_release_ids jsonb,
  metadata jsonb not null default '{}'::jsonb,
  request_id text,
  created_at timestamptz not null default now()
);
create index if not exists coding_audit_practice_time_idx on public.coding_audit_event(practice_id, created_at desc);
create index if not exists coding_audit_actor_time_idx on public.coding_audit_event(actor_user_id, created_at desc);

alter table public.coding_source_release enable row level security;
alter table public.sa_icd10_code enable row level security;
alter table public.icd10_search_alias enable row level security;
alter table public.sa_icd10_import_staging enable row level security;
alter table public.coding_ingestion_job enable row level security;
alter table public.coding_audit_event enable row level security;

drop policy if exists coding_sources_member_read on public.coding_source_release;
create policy coding_sources_member_read
on public.coding_source_release for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid()) and m.active = true
));

drop policy if exists coding_codes_member_read on public.sa_icd10_code;
create policy coding_codes_member_read
on public.sa_icd10_code for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid()) and m.active = true
));

drop policy if exists coding_aliases_member_read on public.icd10_search_alias;
create policy coding_aliases_member_read
on public.icd10_search_alias for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid()) and m.active = true
));

drop policy if exists coding_audit_member_read on public.coding_audit_event;
create policy coding_audit_member_read
on public.coding_audit_event for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_audit_event.practice_id
    and m.active = true
));

drop policy if exists coding_audit_member_insert on public.coding_audit_event;
create policy coding_audit_member_insert
on public.coding_audit_event for insert
to authenticated
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_audit_event.practice_id
      and m.active = true
  )
);

revoke all on table public.coding_source_release from anon, authenticated;
revoke all on table public.sa_icd10_code from anon, authenticated;
revoke all on table public.icd10_search_alias from anon, authenticated;
revoke all on table public.sa_icd10_import_staging from anon, authenticated;
revoke all on table public.coding_ingestion_job from anon, authenticated;
revoke all on table public.coding_audit_event from anon, authenticated;

grant select on table public.coding_source_release to authenticated;
grant select on table public.sa_icd10_code to authenticated;
grant select on table public.icd10_search_alias to authenticated;
grant select, insert on table public.coding_audit_event to authenticated;

create or replace function public.search_sa_icd10(
  p_query text,
  p_source_release_id uuid default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  code text,
  official_description text,
  valid_clinical_use boolean,
  valid_primary boolean,
  valid_asterisk boolean,
  valid_dagger boolean,
  valid_sequelae boolean,
  age_range text,
  gender public.coding_gender_rule,
  source_release_id uuid,
  sa_start_date date,
  sa_end_date date,
  match_reason text,
  relevance double precision
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with q as (
    select
      trim(p_query) as raw,
      upper(regexp_replace(trim(p_query), '[^A-Za-z0-9*]+', '', 'g')) as code_q,
      lower(trim(p_query)) as text_q
  ), selected_release as (
    select coalesce(
      p_source_release_id,
      (
        select csr.id
        from public.coding_source_release csr
        where csr.authority = 'NDOH'
          and csr.source_name = 'ICD-10 Master Industry Table'
          and csr.status = 'active'
        order by csr.effective_from desc nulls last, csr.created_at desc
        limit 1
      )
    ) as release_id
  ), candidates as (
    select
      c.*,
      case
        when c.normalized_code = q.code_q then 'exact_code'
        when c.normalized_code like q.code_q || '%' and length(q.code_q) >= 2 then 'code_prefix'
        when lower(c.official_description) = q.text_q then 'exact_description'
        when a.alias_normalized = q.text_q then 'exact_alias'
        when to_tsvector('simple', c.official_description) @@ plainto_tsquery('simple', q.raw) then 'full_text'
        when similarity(lower(c.official_description), q.text_q) >= 0.28 then 'fuzzy_description'
        when similarity(coalesce(a.alias_normalized,''), q.text_q) >= 0.32 then 'fuzzy_alias'
        else null
      end as match_reason,
      greatest(
        case when c.normalized_code = q.code_q then 1.0 else 0.0 end,
        case when c.normalized_code like q.code_q || '%' and length(q.code_q) >= 2 then 0.90 else 0.0 end,
        case when lower(c.official_description) = q.text_q then 0.95 else 0.0 end,
        case when a.alias_normalized = q.text_q then 0.92 else 0.0 end,
        similarity(lower(c.official_description), q.text_q),
        similarity(coalesce(a.alias_normalized,''), q.text_q)
      )::double precision as relevance
    from public.sa_icd10_code c
    cross join q
    cross join selected_release sr
    left join public.icd10_search_alias a
      on a.icd10_code_id = c.id and a.review_status = 'approved'
    where c.source_release_id = sr.release_id
      and (
        c.normalized_code = q.code_q
        or (length(q.code_q) >= 2 and c.normalized_code like q.code_q || '%')
        or lower(c.official_description) = q.text_q
        or a.alias_normalized = q.text_q
        or to_tsvector('simple', c.official_description) @@ plainto_tsquery('simple', q.raw)
        or similarity(lower(c.official_description), q.text_q) >= 0.28
        or similarity(coalesce(a.alias_normalized,''), q.text_q) >= 0.32
      )
  )
  select d.id,
         d.code,
         d.official_description,
         d.valid_clinical_use,
         d.valid_primary,
         d.valid_asterisk,
         d.valid_dagger,
         d.valid_sequelae,
         d.age_range,
         d.gender,
         d.source_release_id,
         d.sa_start_date,
         d.sa_end_date,
         d.match_reason,
         d.relevance
  from (
    select distinct on (c.id)
      c.id,
      c.code,
      c.official_description,
      c.valid_clinical_use,
      c.valid_primary,
      c.valid_asterisk,
      c.valid_dagger,
      c.valid_sequelae,
      c.age_range,
      c.gender,
      c.source_release_id,
      c.sa_start_date,
      c.sa_end_date,
      c.match_reason,
      c.relevance
    from candidates c
    where c.match_reason is not null
    order by c.id, c.relevance desc
  ) d
  order by d.relevance desc, d.valid_clinical_use desc, d.code
  limit greatest(1, least(coalesce(p_limit,20), 50));
$$;

revoke all on function public.search_sa_icd10(text, uuid, integer) from public;
grant execute on function public.search_sa_icd10(text, uuid, integer) to authenticated;

commit;
