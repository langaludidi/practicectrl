
begin;

do $$ begin
  create type public.integration_provider_type as enum (
    'regulator','standards_body','coding_authority','coding_licensor',
    'claims_switch','data_vendor','medical_scheme','administrator',
    'managed_care','communications','payments','other'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.integration_lifecycle_status as enum (
    'research','contact_required','contracting','sandbox_pending',
    'sandbox_active','production_ready','active','blocked','retired'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.integration_interface_type as enum (
    'api','edi_file','sftp','webhook','portal','manual_download',
    'licensed_dataset','database_feed','other'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.integration_direction as enum (
    'inbound','outbound','bidirectional'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.integration_sync_mode as enum (
    'realtime','batch','both','manual'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.integration_support_level as enum (
    'confirmed_public','contract_required','specification_required',
    'sandbox_required','research_required','not_supported'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.platform_module (
  id uuid primary key default gen_random_uuid(),
  module_key text not null unique,
  display_name text not null,
  descriptor text,
  flagship boolean not null default false,
  enabled_by_default boolean not null default false,
  ai_enabled boolean not null default true,
  voice_enabled boolean not null default true,
  status text not null default 'planned'
    check (status in ('planned','foundation','development','uat','active','retired')),
  created_at timestamptz not null default now()
);

create table if not exists public.practice_module (
  practice_id uuid not null references public.practice(id) on delete cascade,
  module_id uuid not null references public.platform_module(id) on delete restrict,
  enabled boolean not null default false,
  enabled_at timestamptz,
  configuration jsonb not null default '{}'::jsonb,
  primary key (practice_id,module_id)
);

create table if not exists public.integration_provider (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  provider_type public.integration_provider_type not null,
  country_code text not null default 'ZA',
  website_url text,
  authoritative_for text[] not null default '{}',
  commercial_agreement_required boolean not null default false,
  accreditation_required boolean not null default false,
  lifecycle_status public.integration_lifecycle_status not null default 'research',
  notes text,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.integration_interface (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  name text not null,
  interface_type public.integration_interface_type not null,
  direction public.integration_direction not null,
  sync_mode public.integration_sync_mode not null,
  auth_method text,
  documentation_url text,
  specification_reference text,
  accreditation_required boolean not null default false,
  contract_required boolean not null default false,
  sandbox_available boolean,
  status public.integration_lifecycle_status not null default 'research',
  notes text,
  created_at timestamptz not null default now(),
  unique(provider_id,name)
);

create table if not exists public.integration_capability_catalog (
  code text primary key,
  display_name text not null,
  domain text not null,
  description text not null,
  requires_patient_context boolean not null default false,
  transactional boolean not null default false
);

create table if not exists public.integration_capability (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  interface_id uuid references public.integration_interface(id) on delete restrict,
  capability_code text not null references public.integration_capability_catalog(code) on delete restrict,
  support_level public.integration_support_level not null,
  evidence_url text,
  evidence_note text,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique(provider_id, capability_code, interface_id)
);

create table if not exists public.source_dataset (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  dataset_key text not null,
  name text not null,
  domain text not null,
  authority_level text not null
    check (authority_level in ('canonical','regulatory','licensed','transactional','reference')),
  access_model text not null
    check (access_model in ('public_download','licensed_file','api','portal','contract_feed','manual')),
  licence_required boolean not null default false,
  versioned_required boolean not null default true,
  provenance_required boolean not null default true,
  effective_dating_required boolean not null default true,
  update_frequency text,
  evidence_url text,
  status public.integration_lifecycle_status not null default 'research',
  notes text,
  created_at timestamptz not null default now(),
  unique(provider_id,dataset_key)
);

create table if not exists public.integration_requirement (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  interface_id uuid references public.integration_interface(id) on delete restrict,
  requirement_type text not null
    check (requirement_type in (
      'commercial_contact','nda','contract','data_licence','accreditation',
      'technical_specification','sandbox_credentials','production_credentials',
      'pricing','data_processing_agreement','consent','security_review','other'
    )),
  title text not null,
  description text not null,
  priority text not null default 'medium'
    check (priority in ('critical','high','medium','low')),
  status text not null default 'open'
    check (status in ('open','in_progress','waiting_external','completed','blocked','not_required')),
  owner text,
  due_date date,
  external_reference text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.practice_integration_connection (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  provider_id uuid not null references public.integration_provider(id) on delete restrict,
  interface_id uuid references public.integration_interface(id) on delete restrict,
  environment text not null default 'sandbox'
    check (environment in ('sandbox','production')),
  status public.integration_lifecycle_status not null default 'research',
  external_account_ref text,
  credential_secret_ref text,
  configuration jsonb not null default '{}'::jsonb,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(practice_id,provider_id,interface_id,environment)
);

create index if not exists integration_interface_provider_idx on public.integration_interface(provider_id);
create index if not exists integration_capability_provider_idx on public.integration_capability(provider_id);
create index if not exists integration_requirement_provider_status_idx on public.integration_requirement(provider_id,status,priority);
create index if not exists source_dataset_provider_idx on public.source_dataset(provider_id);
create index if not exists practice_integration_connection_practice_idx on public.practice_integration_connection(practice_id,status);

alter table public.platform_module enable row level security;
alter table public.practice_module enable row level security;
alter table public.integration_provider enable row level security;
alter table public.integration_interface enable row level security;
alter table public.integration_capability_catalog enable row level security;
alter table public.integration_capability enable row level security;
alter table public.source_dataset enable row level security;
alter table public.integration_requirement enable row level security;
alter table public.practice_integration_connection enable row level security;

-- Staff can read the shared platform/integration catalogue.
revoke all on table public.platform_module from anon, authenticated;
revoke all on table public.integration_provider from anon, authenticated;
revoke all on table public.integration_interface from anon, authenticated;
revoke all on table public.integration_capability_catalog from anon, authenticated;
revoke all on table public.integration_capability from anon, authenticated;
revoke all on table public.source_dataset from anon, authenticated;
grant select on table public.platform_module to authenticated;
grant select on table public.integration_provider to authenticated;
grant select on table public.integration_interface to authenticated;
grant select on table public.integration_capability_catalog to authenticated;
grant select on table public.integration_capability to authenticated;
grant select on table public.source_dataset to authenticated;

create policy platform_module_staff_read on public.platform_module
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

create policy integration_provider_staff_read on public.integration_provider
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

create policy integration_interface_staff_read on public.integration_interface
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

create policy integration_capability_catalog_staff_read on public.integration_capability_catalog
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

create policy integration_capability_staff_read on public.integration_capability
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

create policy source_dataset_staff_read on public.source_dataset
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

-- Tenant/module state is tenant-scoped.
revoke all on table public.practice_module from anon, authenticated;
grant select on table public.practice_module to authenticated;
create policy practice_module_staff_read on public.practice_module
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid())
    and m.practice_id=practice_module.practice_id
    and m.active
));

-- Commercial requirements and connection configuration are restricted to
-- practice managers/system admins. No secret value is stored, only a secret reference.
revoke all on table public.integration_requirement from anon, authenticated;
revoke all on table public.practice_integration_connection from anon, authenticated;
grant select on table public.integration_requirement to authenticated;
grant select on table public.practice_integration_connection to authenticated;

create policy integration_requirement_privileged_read on public.integration_requirement
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid())
    and m.active
    and m.role in ('practice_manager','system_admin')
));

create policy practice_integration_connection_privileged_read on public.practice_integration_connection
for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid())
    and m.practice_id=practice_integration_connection.practice_id
    and m.active
    and m.role in ('practice_manager','system_admin')
));

commit;
