begin;

do $$ begin
  create type public.assist_data_class as enum ('none','personal','health_special');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.assist_capability_type as enum ('ai','voice','deterministic');
exception when duplicate_object then null; end $$;

create table if not exists public.assist_capability (
  capability_key text primary key,
  display_name text not null,
  capability_type public.assist_capability_type not null,
  module_key text references public.platform_module(module_key) on delete restrict,
  description text not null,
  maximum_data_class public.assist_data_class not null default 'none',
  requires_human_review boolean not null default true,
  enabled_at_platform boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.assist_provider_config (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null,
  display_name text not null,
  model_id text not null,
  capability_type public.assist_capability_type not null,
  transport_kind text not null check (transport_kind in ('api','browser','local','other')),
  transport_ready boolean not null default false,
  maximum_approved_data_class public.assist_data_class not null default 'none',
  phi_approved boolean not null default false,
  data_processing_reference text,
  retention_summary text,
  region_summary text,
  credential_secret_ref text,
  configuration jsonb not null default '{}'::jsonb,
  review_status text not null default 'pending'
    check (review_status in ('pending','approved','rejected','retired')),
  approval_source text not null default 'human'
    check (approval_source in ('human','platform_seed')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider_key,model_id,capability_type),
  constraint assist_provider_approval_ck check (
    review_status <> 'approved'
    or (reviewed_at is not null and (reviewed_by is not null or approval_source='platform_seed'))
  ),
  constraint assist_provider_health_ck check (
    maximum_approved_data_class <> 'health_special' or phi_approved
  )
);
create index if not exists assist_provider_reviewed_by_idx
  on public.assist_provider_config(reviewed_by) where reviewed_by is not null;

create table if not exists public.practice_assist_policy (
  practice_id uuid not null references public.practice(id) on delete cascade,
  capability_key text not null references public.assist_capability(capability_key) on delete restrict,
  provider_config_id uuid references public.assist_provider_config(id) on delete restrict,
  enabled boolean not null default false,
  allowed_data_class public.assist_data_class not null default 'none',
  max_input_chars integer not null default 4000 check (max_input_chars between 1 and 50000),
  retain_raw_input boolean not null default false,
  retain_raw_output boolean not null default false,
  require_aal2 boolean not null default true,
  human_review_required boolean not null default true,
  consent_basis text,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  configuration jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(practice_id,capability_key),
  constraint practice_assist_enable_ck check (
    not enabled or approved_by is not null
  ),
  constraint practice_assist_no_raw_health_ck check (
    allowed_data_class <> 'health_special'
    or (retain_raw_input=false and retain_raw_output=false)
  )
);
create index if not exists practice_assist_provider_idx
  on public.practice_assist_policy(provider_config_id) where provider_config_id is not null;
create index if not exists practice_assist_approved_by_idx
  on public.practice_assist_policy(approved_by) where approved_by is not null;

create table if not exists public.assist_interaction (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  capability_key text not null references public.assist_capability(capability_key) on delete restrict,
  provider_config_id uuid references public.assist_provider_config(id) on delete restrict,
  module_key text,
  encounter_id uuid,
  input_sha256 text not null check (input_sha256 ~ '^[a-f0-9]{64}$'),
  input_char_count integer not null check (input_char_count >= 0),
  output_sha256 text check (output_sha256 is null or output_sha256 ~ '^[a-f0-9]{64}$'),
  output_char_count integer check (output_char_count is null or output_char_count >= 0),
  data_class public.assist_data_class not null,
  raw_input_stored boolean not null default false,
  raw_output_stored boolean not null default false,
  status text not null check (status in ('started','completed','failed','discarded')),
  error_code text,
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint assist_interaction_complete_ck check (
    status='started' or completed_at is not null
  ),
  constraint assist_interaction_health_storage_ck check (
    data_class <> 'health_special'
    or (raw_input_stored=false and raw_output_stored=false)
  )
);
create index if not exists assist_interaction_practice_idx
  on public.assist_interaction(practice_id,started_at desc);
create index if not exists assist_interaction_actor_idx
  on public.assist_interaction(actor_user_id,started_at desc);
create index if not exists assist_interaction_capability_idx
  on public.assist_interaction(capability_key,started_at desc);
create index if not exists assist_interaction_provider_idx
  on public.assist_interaction(provider_config_id) where provider_config_id is not null;

alter table public.assist_capability enable row level security;
alter table public.assist_provider_config enable row level security;
alter table public.practice_assist_policy enable row level security;
alter table public.assist_interaction enable row level security;

revoke all on table public.assist_capability from anon,authenticated;
revoke all on table public.assist_provider_config from anon,authenticated;
revoke all on table public.practice_assist_policy from anon,authenticated;
revoke all on table public.assist_interaction from anon,authenticated;

grant select on table public.assist_capability to authenticated;
grant select(
  id,provider_key,display_name,model_id,capability_type,transport_kind,
  transport_ready,maximum_approved_data_class,phi_approved,
  data_processing_reference,retention_summary,region_summary,
  review_status,approval_source,reviewed_at,created_at,updated_at
) on public.assist_provider_config to authenticated;
grant select on table public.practice_assist_policy to authenticated;
grant select on table public.assist_interaction to authenticated;

drop policy if exists assist_capability_staff_read on public.assist_capability;
create policy assist_capability_staff_read
on public.assist_capability for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

drop policy if exists assist_provider_staff_read on public.assist_provider_config;
create policy assist_provider_staff_read
on public.assist_provider_config for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

drop policy if exists practice_assist_staff_read on public.practice_assist_policy;
create policy practice_assist_staff_read
on public.practice_assist_policy for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid())
    and m.practice_id=practice_assist_policy.practice_id
    and m.active
));

drop policy if exists assist_interaction_own_or_privileged_read on public.assist_interaction;
create policy assist_interaction_own_or_privileged_read
on public.assist_interaction for select to authenticated
using (
  actor_user_id=(select auth.uid())
  or exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=assist_interaction.practice_id
      and m.active
      and m.role in ('practice_manager','system_admin','auditor')
  )
);

insert into public.assist_capability(
  capability_key,display_name,capability_type,module_key,description,
  maximum_data_class,requires_human_review,enabled_at_platform
)
values
('code10.clinical_concept_extraction','Code10 clinical concept extraction','ai','code10',
 'Extract documented clinical concepts and documentation questions from minimal clinical narrative. Never assigns final ICD-10 codes.',
 'health_special',true,true),
('code10.voice_dictation','Code10 browser voice dictation','voice','code10',
 'Convert spoken search/narrative input into text using browser speech-recognition capability where supported. PracticeCtrl does not store audio in this mode.',
 'health_special',true,true),
('code10.voice_commands','Code10 deterministic voice commands','deterministic','code10',
 'Interpret a limited local command grammar for Code10 navigation and search actions. No external model call is required.',
 'health_special',true,true),
('crm.assistant','CRM AI assistant','ai','crm',
 'Future CRM task/contact/follow-up assistance. Disabled until separately governed and implemented.',
 'personal',true,false),
('billing.assistant','Billing AI assistant','ai','billing',
 'Future billing explanation and workflow assistance. Disabled until separately governed and implemented.',
 'health_special',true,false),
('claims_revenue.assistant','Claims and revenue AI assistant','ai','claims_revenue',
 'Future claim-response, ERA and revenue-integrity assistance. Disabled until separately governed and implemented.',
 'health_special',true,false)
on conflict (capability_key) do update set
  display_name=excluded.display_name,
  capability_type=excluded.capability_type,
  module_key=excluded.module_key,
  description=excluded.description,
  maximum_data_class=excluded.maximum_data_class,
  requires_human_review=excluded.requires_human_review,
  enabled_at_platform=excluded.enabled_at_platform,
  updated_at=now();

insert into public.assist_provider_config(
  provider_key,display_name,model_id,capability_type,transport_kind,
  transport_ready,maximum_approved_data_class,phi_approved,
  retention_summary,region_summary,review_status,approval_source,reviewed_at,configuration
)
values
('browser-speech-recognition','Browser Speech Recognition','browser-managed','voice','browser',
 true,'health_special',true,
 'PracticeCtrl does not retain audio. Browser/platform processing and retention are outside PracticeCtrl and must be described separately to users.',
 'Browser/platform dependent','approved','platform_seed',now(),
 jsonb_build_object('audio_storage_by_practicectrl',false)),
('practicectrl-local','PracticeCtrl Local Deterministic','voice-command-v1','deterministic','local',
 true,'health_special',true,
 'No external model call. Raw input is not persisted by the command parser.',
 'Application runtime','approved','platform_seed',now(),
 jsonb_build_object('external_processing',false))
on conflict (provider_key,model_id,capability_type) do update set
  display_name=excluded.display_name,
  transport_kind=excluded.transport_kind,
  transport_ready=excluded.transport_ready,
  maximum_approved_data_class=excluded.maximum_approved_data_class,
  phi_approved=excluded.phi_approved,
  retention_summary=excluded.retention_summary,
  region_summary=excluded.region_summary,
  review_status=excluded.review_status,
  approval_source=excluded.approval_source,
  reviewed_at=excluded.reviewed_at,
  configuration=excluded.configuration,
  updated_at=now();

commit;
