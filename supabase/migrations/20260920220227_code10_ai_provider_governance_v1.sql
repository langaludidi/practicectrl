
begin;

create table if not exists public.code10_ai_provider_config (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null,
  display_name text not null,
  model_id text not null,
  purpose text not null default 'clinical_concept_extraction'
    check (purpose in ('clinical_concept_extraction')),
  enabled boolean not null default false,
  phi_approved boolean not null default false,
  credential_reference text,
  data_processing_reference text,
  retention_summary text,
  region_summary text,
  configuration jsonb not null default '{}'::jsonb,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider_key,model_id,purpose),
  constraint code10_ai_enable_guard_ck check (
    not enabled or (phi_approved and reviewed_at is not null and reviewed_by is not null)
  )
);

create unique index if not exists code10_one_active_ai_provider_idx
  on public.code10_ai_provider_config(purpose)
  where enabled=true;

create index if not exists code10_ai_reviewed_by_idx
  on public.code10_ai_provider_config(reviewed_by)
  where reviewed_by is not null;

alter table public.code10_ai_provider_config enable row level security;
revoke all on table public.code10_ai_provider_config from anon,authenticated;
grant select(
  id,provider_key,display_name,model_id,purpose,enabled,phi_approved,
  data_processing_reference,retention_summary,region_summary,
  reviewed_at,created_at,updated_at
) on public.code10_ai_provider_config to authenticated;

drop policy if exists code10_ai_provider_staff_read on public.code10_ai_provider_config;
create policy code10_ai_provider_staff_read
on public.code10_ai_provider_config for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

commit;
