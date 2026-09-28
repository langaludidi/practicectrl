
begin;

create table if not exists public.medical_scheme (
  id uuid primary key default gen_random_uuid(),
  cms_registration_number text,
  name text not null,
  scheme_type text check (scheme_type in ('open','restricted','other')),
  regulatory_status text not null default 'active'
    check (regulatory_status in ('active','restricted_status','amalgamated','wound_up','other')),
  effective_from date,
  effective_to date,
  source_dataset_id uuid references public.source_dataset(id) on delete restrict,
  source_reference text,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint medical_scheme_cms_reg_unique unique (cms_registration_number),
  constraint medical_scheme_dates_ck check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);

create table if not exists public.medical_scheme_alias (
  id uuid primary key default gen_random_uuid(),
  medical_scheme_id uuid not null references public.medical_scheme(id) on delete cascade,
  alias text not null,
  alias_normalized text not null,
  source text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(medical_scheme_id,alias_normalized)
);
create index if not exists medical_scheme_alias_normalized_idx
  on public.medical_scheme_alias(alias_normalized);

create table if not exists public.medical_scheme_option (
  id uuid primary key default gen_random_uuid(),
  medical_scheme_id uuid not null references public.medical_scheme(id) on delete restrict,
  benefit_year integer not null check (benefit_year between 2000 and 2100),
  option_name text not null,
  option_code text,
  approval_status text not null default 'approved'
    check (approval_status in ('approved','conditional','discontinued','pending','unknown')),
  effective_from date,
  effective_to date,
  source_dataset_id uuid references public.source_dataset(id) on delete restrict,
  source_reference text,
  created_at timestamptz not null default now(),
  constraint medical_scheme_option_unique unique (medical_scheme_id,benefit_year,option_name),
  constraint medical_scheme_option_dates_ck check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);

create table if not exists public.payer_administration_relationship (
  id uuid primary key default gen_random_uuid(),
  medical_scheme_id uuid not null references public.medical_scheme(id) on delete restrict,
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  relationship_type text not null
    check (relationship_type in ('administrator','managed_care','switch_route','other')),
  effective_from date,
  effective_to date,
  source_dataset_id uuid references public.source_dataset(id) on delete restrict,
  evidence_url text,
  status text not null default 'active'
    check (status in ('active','historical','unverified')),
  created_at timestamptz not null default now(),
  constraint payer_admin_rel_dates_ck check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);
create index if not exists payer_admin_rel_scheme_idx
  on public.payer_administration_relationship(medical_scheme_id,relationship_type);

create table if not exists public.payer_transaction_route (
  id uuid primary key default gen_random_uuid(),
  medical_scheme_id uuid not null references public.medical_scheme(id) on delete restrict,
  medical_scheme_option_id uuid references public.medical_scheme_option(id) on delete restrict,
  capability_code text not null references public.integration_capability_catalog(code) on delete restrict,
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  interface_id uuid references public.integration_interface(id) on delete restrict,
  external_scheme_code text,
  external_option_code text,
  support_status public.integration_support_level not null default 'research_required',
  effective_from date,
  effective_to date,
  evidence_url text,
  notes text,
  created_at timestamptz not null default now(),
  constraint payer_route_dates_ck check (
    effective_to is null or effective_from is null or effective_to >= effective_from
  )
);
create index if not exists payer_transaction_route_lookup_idx
  on public.payer_transaction_route(medical_scheme_id,capability_code,effective_from,effective_to);

create table if not exists public.practice_payer_priority_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  snapshot_date date not null,
  source_label text not null,
  payer_label text not null,
  patient_count integer not null check (patient_count >= 0),
  rank integer not null check (rank > 0),
  canonical_scheme_id uuid references public.medical_scheme(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  unique(practice_id,snapshot_date,payer_label)
);
create index if not exists practice_payer_priority_practice_idx
  on public.practice_payer_priority_snapshot(practice_id,snapshot_date,rank);

alter table public.medical_scheme enable row level security;
alter table public.medical_scheme_alias enable row level security;
alter table public.medical_scheme_option enable row level security;
alter table public.payer_administration_relationship enable row level security;
alter table public.payer_transaction_route enable row level security;
alter table public.practice_payer_priority_snapshot enable row level security;

revoke all on table public.medical_scheme from anon, authenticated;
revoke all on table public.medical_scheme_alias from anon, authenticated;
revoke all on table public.medical_scheme_option from anon, authenticated;
revoke all on table public.payer_administration_relationship from anon, authenticated;
revoke all on table public.payer_transaction_route from anon, authenticated;
revoke all on table public.practice_payer_priority_snapshot from anon, authenticated;

grant select on table public.medical_scheme to authenticated;
grant select on table public.medical_scheme_alias to authenticated;
grant select on table public.medical_scheme_option to authenticated;
grant select on table public.payer_administration_relationship to authenticated;
grant select on table public.payer_transaction_route to authenticated;
grant select on table public.practice_payer_priority_snapshot to authenticated;

create policy medical_scheme_staff_read on public.medical_scheme
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));
create policy medical_scheme_alias_staff_read on public.medical_scheme_alias
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));
create policy medical_scheme_option_staff_read on public.medical_scheme_option
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));
create policy payer_admin_rel_staff_read on public.payer_administration_relationship
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));
create policy payer_transaction_route_staff_read on public.payer_transaction_route
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));
create policy practice_payer_priority_staff_read on public.practice_payer_priority_snapshot
for select to authenticated using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid())
    and m.practice_id=practice_payer_priority_snapshot.practice_id
    and m.active
));

commit;
