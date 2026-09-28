-- Phase 3 integration SQL: rule DSL + CMS PMB intelligence.
begin;

alter table public.coding_rule
  add column if not exists condition_json jsonb,
  add column if not exists outcome_json jsonb,
  add column if not exists implementation_status text not null default 'reference_only'
    check (implementation_status in ('reference_only','deterministic','clinician_prompt')),
  add column if not exists clinical_review_required boolean not null default true;

create table if not exists public.pmb_mapping (
  id uuid primary key default gen_random_uuid(),
  source_release_id uuid not null references public.coding_source_release(id) on delete restrict,
  icd10_code text not null,
  normalized_code text not null,
  pmb_category text,
  dtp_number text,
  cdl_condition text,
  pmb_descriptor text,
  qualification_notes text,
  treatment_context text,
  source_row_number integer,
  raw_source_row jsonb not null default '{}'::jsonb,
  effective_from date,
  effective_to date,
  created_at timestamptz not null default now(),
  constraint pmb_mapping_dates_ck check (effective_to is null or effective_from is null or effective_to >= effective_from),
  constraint pmb_mapping_version_unique unique (source_release_id, normalized_code, pmb_category, dtp_number, cdl_condition, pmb_descriptor)
);

create index if not exists pmb_mapping_release_code_idx
  on public.pmb_mapping(source_release_id, normalized_code);
create index if not exists pmb_mapping_code_idx
  on public.pmb_mapping(normalized_code);
create index if not exists pmb_mapping_dtp_idx
  on public.pmb_mapping(dtp_number) where dtp_number is not null;
create index if not exists pmb_mapping_cdl_idx
  on public.pmb_mapping(cdl_condition) where cdl_condition is not null;

create table if not exists public.pmb_review (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null,
  encounter_id uuid,
  coding_session_id uuid,
  icd10_code_id uuid not null references public.sa_icd10_code(id) on delete restrict,
  pmb_mapping_id uuid references public.pmb_mapping(id) on delete restrict,
  status text not null check (status in ('NOT_IDENTIFIED','POSSIBLE','CLINICAL_REVIEW_REQUIRED','CONFIRMED_BY_CLINICIAN','NOT_APPLICABLE')),
  rationale text,
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint pmb_review_confirmation_ck check (
    status not in ('CONFIRMED_BY_CLINICIAN','NOT_APPLICABLE')
    or (reviewed_by is not null and reviewed_at is not null)
  )
);

create index if not exists pmb_review_practice_time_idx
  on public.pmb_review(practice_id, created_at desc);
create index if not exists pmb_review_encounter_idx
  on public.pmb_review(encounter_id) where encounter_id is not null;

create table if not exists public.pmb_import_staging (
  import_batch_id uuid not null,
  row_number integer not null,
  raw_row jsonb not null,
  mapped_row jsonb,
  parse_status text not null default 'pending' check (parse_status in ('pending','valid','invalid','needs_mapping')),
  parse_error text,
  created_at timestamptz not null default now(),
  primary key (import_batch_id, row_number)
);

alter table public.pmb_mapping enable row level security;
alter table public.pmb_review enable row level security;
alter table public.pmb_import_staging enable row level security;

revoke all on table public.pmb_mapping from anon, authenticated;
revoke all on table public.pmb_review from anon, authenticated;
revoke all on table public.pmb_import_staging from anon, authenticated;

grant select on table public.pmb_mapping to authenticated;
grant select, insert, update on table public.pmb_review to authenticated;

drop policy if exists pmb_mapping_member_read on public.pmb_mapping;
create policy pmb_mapping_member_read
on public.pmb_mapping for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid()) and m.active = true
));

drop policy if exists pmb_review_member_read on public.pmb_review;
create policy pmb_review_member_read
on public.pmb_review for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = pmb_review.practice_id
    and m.active = true
));

drop policy if exists pmb_review_member_insert on public.pmb_review;
create policy pmb_review_member_insert
on public.pmb_review for insert
to authenticated
with check (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = pmb_review.practice_id
    and m.active = true
));

drop policy if exists pmb_review_member_update on public.pmb_review;
create policy pmb_review_member_update
on public.pmb_review for update
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = pmb_review.practice_id
    and m.active = true
))
with check (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = pmb_review.practice_id
    and m.active = true
));

create or replace function public.get_possible_pmb_relationships(
  p_icd10_code text,
  p_source_release_id uuid default null
)
returns table (
  id uuid,
  source_release_id uuid,
  icd10_code text,
  pmb_category text,
  dtp_number text,
  cdl_condition text,
  pmb_descriptor text,
  qualification_notes text,
  treatment_context text
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with selected_release as (
    select coalesce(
      p_source_release_id,
      (
        select csr.id
        from public.coding_source_release csr
        where csr.authority = 'CMS'
          and csr.status = 'active'
        order by csr.published_date desc nulls last, csr.created_at desc
        limit 1
      )
    ) as release_id
  )
  select p.id,
         p.source_release_id,
         p.icd10_code,
         p.pmb_category,
         p.dtp_number,
         p.cdl_condition,
         p.pmb_descriptor,
         p.qualification_notes,
         p.treatment_context
  from public.pmb_mapping p
  cross join selected_release sr
  where p.source_release_id = sr.release_id
    and p.normalized_code = upper(regexp_replace(trim(p_icd10_code), '[^A-Za-z0-9*]+', '', 'g'))
  order by p.pmb_category nulls last, p.dtp_number nulls last, p.cdl_condition nulls last;
$$;

revoke all on function public.get_possible_pmb_relationships(text, uuid) from public, anon;
grant execute on function public.get_possible_pmb_relationships(text, uuid) to authenticated;

commit;
