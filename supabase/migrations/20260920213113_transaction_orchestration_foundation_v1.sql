
begin;

create table if not exists public.integration_retry_policy (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete cascade,
  interface_id uuid not null references public.integration_interface(id) on delete cascade,
  capability_code text not null references public.integration_capability_catalog(code) on delete restrict,
  environment text not null check (environment in ('sandbox','production')),
  max_attempts integer not null default 1 check (max_attempts between 1 and 10),
  timeout_ms integer not null default 15000 check (timeout_ms between 500 and 180000),
  backoff_strategy text not null default 'exponential'
    check (backoff_strategy in ('fixed','exponential')),
  initial_delay_ms integer not null default 1000 check (initial_delay_ms between 0 and 60000),
  max_delay_ms integer not null default 30000 check (max_delay_ms between 0 and 300000),
  jitter_ratio numeric(4,3) not null default 0.100
    check (jitter_ratio between 0 and 1),
  retryable_error_classes text[] not null default array['timeout','transport','rate_limit','vendor_temporary'],
  active boolean not null default false,
  source_reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider_id,interface_id,capability_code,environment)
);

alter table public.payer_transaction
  add column if not exists environment text not null default 'sandbox'
    check (environment in ('sandbox','production')),
  add column if not exists idempotency_key text,
  add column if not exists contract_version text not null default '1',
  add column if not exists adapter_version text,
  add column if not exists retry_policy_id uuid references public.integration_retry_policy(id) on delete restrict,
  add column if not exists attempt_count integer not null default 0 check (attempt_count >= 0),
  add column if not exists max_attempts integer not null default 1 check (max_attempts between 1 and 10),
  add column if not exists timeout_at timestamptz,
  add column if not exists next_retry_at timestamptz,
  add column if not exists response_sha256 text,
  add column if not exists error_class text
    check (error_class is null or error_class in (
      'timeout','transport','rate_limit','authentication','authorisation',
      'configuration','protocol','vendor_temporary','vendor_permanent',
      'validation','unknown'
    )),
  add column if not exists error_code text,
  add column if not exists error_summary text;

alter table public.payer_transaction
  alter column idempotency_key set not null;

create unique index if not exists payer_transaction_idempotency_uq
  on public.payer_transaction(
    practice_id,provider_id,interface_id,capability_code,environment,idempotency_key
  );

create index if not exists payer_transaction_retry_policy_idx
  on public.payer_transaction(retry_policy_id)
  where retry_policy_id is not null;

create index if not exists payer_transaction_retry_queue_idx
  on public.payer_transaction(transaction_status,next_retry_at)
  where transaction_status in ('queued','failed','timed_out');

create table if not exists public.payer_transaction_attempt (
  id uuid primary key default gen_random_uuid(),
  payer_transaction_id uuid not null references public.payer_transaction(id) on delete restrict,
  attempt_no integer not null check (attempt_no > 0),
  attempt_status text not null default 'started'
    check (attempt_status in ('started','sent','completed','failed','timed_out','cancelled')),
  request_sha256 text,
  response_sha256 text,
  external_transaction_ref text,
  http_status integer check (http_status is null or http_status between 100 and 599),
  error_class text
    check (error_class is null or error_class in (
      'timeout','transport','rate_limit','authentication','authorisation',
      'configuration','protocol','vendor_temporary','vendor_permanent',
      'validation','unknown'
    )),
  error_code text,
  error_summary text,
  retryable boolean not null default false,
  retry_after_seconds integer check (retry_after_seconds is null or retry_after_seconds >= 0),
  started_at timestamptz not null default now(),
  sent_at timestamptz,
  completed_at timestamptz,
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  created_at timestamptz not null default now(),
  unique(payer_transaction_id,attempt_no)
);
create index if not exists payer_transaction_attempt_tx_idx
  on public.payer_transaction_attempt(payer_transaction_id,attempt_no);

create table if not exists public.payer_transaction_payload (
  id uuid primary key default gen_random_uuid(),
  payer_transaction_id uuid not null references public.payer_transaction(id) on delete restrict,
  attempt_id uuid references public.payer_transaction_attempt(id) on delete restrict,
  payload_role text not null
    check (payload_role in ('request','response','acknowledgement','error','era')),
  representation text not null default 'normalized_json'
    check (representation in ('normalized_json','vendor_wire')),
  bucket_id text not null default 'switch-payloads',
  object_path text not null,
  content_type text not null,
  byte_size bigint not null check (byte_size >= 0),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  unique(bucket_id,object_path)
);
create index if not exists payer_transaction_payload_tx_idx
  on public.payer_transaction_payload(payer_transaction_id,created_at);
create index if not exists payer_transaction_payload_attempt_idx
  on public.payer_transaction_payload(attempt_id)
  where attempt_id is not null;

create table if not exists public.payer_transaction_result (
  id uuid primary key default gen_random_uuid(),
  payer_transaction_id uuid not null unique references public.payer_transaction(id) on delete restrict,
  capability_code text not null references public.integration_capability_catalog(code) on delete restrict,
  result_status text not null,
  schema_version text not null default '1',
  normalized_result jsonb not null,
  response_sha256 text,
  created_at timestamptz not null default now()
);
create index if not exists payer_transaction_result_capability_idx
  on public.payer_transaction_result(capability_code,result_status);

create table if not exists public.payer_transaction_event (
  id uuid primary key default gen_random_uuid(),
  payer_transaction_id uuid not null references public.payer_transaction(id) on delete restrict,
  attempt_id uuid references public.payer_transaction_attempt(id) on delete restrict,
  event_type text not null
    check (event_type in (
      'created','deduplicated','queued','attempt_started','sent',
      'response_received','completed','retry_scheduled','failed',
      'timed_out','cancelled','payload_stored'
    )),
  from_status text,
  to_status text,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists payer_transaction_event_tx_idx
  on public.payer_transaction_event(payer_transaction_id,created_at desc);
create index if not exists payer_transaction_event_attempt_idx
  on public.payer_transaction_event(attempt_id)
  where attempt_id is not null;

alter table public.integration_retry_policy enable row level security;
alter table public.payer_transaction_attempt enable row level security;
alter table public.payer_transaction_payload enable row level security;
alter table public.payer_transaction_result enable row level security;
alter table public.payer_transaction_event enable row level security;

revoke all on table public.integration_retry_policy from anon,authenticated;
revoke all on table public.payer_transaction_attempt from anon,authenticated;
revoke all on table public.payer_transaction_payload from anon,authenticated;
revoke all on table public.payer_transaction_result from anon,authenticated;
revoke all on table public.payer_transaction_event from anon,authenticated;

grant select on table public.integration_retry_policy to authenticated;
grant select on table public.payer_transaction_attempt to authenticated;
grant select on table public.payer_transaction_result to authenticated;
grant select on table public.payer_transaction_event to authenticated;
grant select on table public.payer_transaction_payload to authenticated;

drop policy if exists integration_retry_policy_finance_read on public.integration_retry_policy;
create policy integration_retry_policy_finance_read
on public.integration_retry_policy for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));

drop policy if exists payer_transaction_attempt_finance_read on public.payer_transaction_attempt;
create policy payer_transaction_attempt_finance_read
on public.payer_transaction_attempt for select to authenticated
using (exists (
  select 1
  from public.payer_transaction t
  join public.practice_staff_member m on m.practice_id=t.practice_id
  where t.id=payer_transaction_attempt.payer_transaction_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));

drop policy if exists payer_transaction_result_finance_read on public.payer_transaction_result;
create policy payer_transaction_result_finance_read
on public.payer_transaction_result for select to authenticated
using (exists (
  select 1
  from public.payer_transaction t
  join public.practice_staff_member m on m.practice_id=t.practice_id
  where t.id=payer_transaction_result.payer_transaction_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));

drop policy if exists payer_transaction_event_finance_read on public.payer_transaction_event;
create policy payer_transaction_event_finance_read
on public.payer_transaction_event for select to authenticated
using (exists (
  select 1
  from public.payer_transaction t
  join public.practice_staff_member m on m.practice_id=t.practice_id
  where t.id=payer_transaction_event.payer_transaction_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));

drop policy if exists payer_transaction_payload_privileged_read on public.payer_transaction_payload;
create policy payer_transaction_payload_privileged_read
on public.payer_transaction_payload for select to authenticated
using (exists (
  select 1
  from public.payer_transaction t
  join public.practice_staff_member m on m.practice_id=t.practice_id
  where t.id=payer_transaction_payload.payer_transaction_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('system_admin','auditor')
));

-- Switch-originated transaction records are server-written only.
revoke insert,update,delete on table public.payer_transaction from authenticated;
revoke insert,update,delete on table public.claim_response_message from authenticated;
revoke insert on table public.remittance_advice from authenticated;
revoke insert on table public.remittance_line from authenticated;

-- Preserve controlled reconciliation updates for authenticated finance users.
grant update (status,reconciled_at,reconciled_by)
  on table public.remittance_advice to authenticated;
grant update (claim_id,claim_line_id)
  on table public.remittance_line to authenticated;

-- Private raw/normalized transaction payload storage. Client users receive read-only
-- access only if they are system administrators or auditors in the owning practice.
insert into storage.buckets(
  id,name,public,file_size_limit,allowed_mime_types,versioning_status
)
values (
  'switch-payloads','switch-payloads',false,26214400,
  array['application/json','application/xml','text/xml','text/plain','application/octet-stream'],
  'DISABLED'
)
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists switch_payloads_privileged_select on storage.objects;
create policy switch_payloads_privileged_select
on storage.objects for select to authenticated
using (
  bucket_id='switch-payloads'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.active
      and m.role in ('system_admin','auditor')
      and m.practice_id::text=split_part(name,'/',1)
  )
);

-- Intentionally no authenticated INSERT/UPDATE/DELETE policy on switch-payloads.
-- Trusted server code uses the Supabase secret key and writes immutable object paths.

-- Internal deterministic sandbox rail.
insert into public.integration_provider(
  slug,name,provider_type,website_url,authoritative_for,
  commercial_agreement_required,accreditation_required,lifecycle_status,notes,last_verified_at
)
values (
  'practicectrl-sandbox','PracticeCtrl Sandbox','other',null,
  array['Synthetic integration testing'],false,false,'sandbox_active',
  'Internal deterministic adapter used only for development/UAT. It cannot execute in production.',
  now()
)
on conflict (slug) do update set
  lifecycle_status='sandbox_active',
  notes=excluded.notes,
  last_verified_at=now();

insert into public.integration_interface(
  provider_id,name,interface_type,direction,sync_mode,auth_method,
  accreditation_required,contract_required,sandbox_available,status,notes
)
select id,'PracticeCtrl deterministic sandbox','api','bidirectional','realtime',
       'internal',false,false,true,'sandbox_active',
       'Synthetic only. No real scheme/member/claim traffic.'
from public.integration_provider
where slug='practicectrl-sandbox'
on conflict (provider_id,name) do update set
  sandbox_available=true,status='sandbox_active',notes=excluded.notes;

insert into public.integration_capability(
  provider_id,interface_id,capability_code,support_level,evidence_note,last_verified_at
)
select p.id,i.id,c.code,'sandbox_required',
       'Internal deterministic sandbox implementation for PracticeCtrl conformance and orchestration testing.',
       now()
from public.integration_provider p
join public.integration_interface i on i.provider_id=p.id
cross join public.integration_capability_catalog c
where p.slug='practicectrl-sandbox'
  and i.name='PracticeCtrl deterministic sandbox'
  and c.code in (
    'member_validation','family_validation','benefit_check','authorisation_rule_check',
    'claim_submit','claim_response','claim_amend','claim_reverse','era_receive'
  )
on conflict (provider_id,capability_code,interface_id) do update set
  support_level='sandbox_required',
  evidence_note=excluded.evidence_note,
  last_verified_at=now();

insert into public.integration_adapter_capability(
  provider_id,interface_id,capability_code,implementation_status,
  executable_sandbox,executable_production,suite_version,last_conformance_at,
  conformance_result,notes
)
select p.id,i.id,c.code,'conformance_passed',true,false,'1',now(),
       jsonb_build_object('deterministic',true,'production_blocked',true),
       'Internal sandbox adapter passes PracticeCtrl normalized-contract conformance. Production execution is prohibited.'
from public.integration_provider p
join public.integration_interface i on i.provider_id=p.id
cross join public.integration_capability_catalog c
where p.slug='practicectrl-sandbox'
  and i.name='PracticeCtrl deterministic sandbox'
  and c.code in (
    'member_validation','family_validation','benefit_check','authorisation_rule_check',
    'claim_submit','claim_response','claim_amend','claim_reverse','era_receive'
  )
on conflict (provider_id,interface_id,capability_code) do update set
  implementation_status='conformance_passed',
  executable_sandbox=true,
  executable_production=false,
  last_conformance_at=now(),
  conformance_result=excluded.conformance_result,
  notes=excluded.notes;

insert into public.practice_integration_connection(
  practice_id,provider_id,interface_id,environment,status,configuration
)
select pr.id,p.id,i.id,'sandbox','sandbox_active',
       jsonb_build_object('synthetic_only',true,'production_blocked',true)
from public.practice pr
join public.integration_provider p on p.slug='practicectrl-sandbox'
join public.integration_interface i on i.provider_id=p.id
where pr.name='Dr Tembisa Tini Inc'
  and i.name='PracticeCtrl deterministic sandbox'
on conflict (practice_id,provider_id,interface_id,environment) do update set
  status='sandbox_active',
  configuration=excluded.configuration,
  updated_at=now();

insert into public.integration_retry_policy(
  provider_id,interface_id,capability_code,environment,max_attempts,timeout_ms,
  backoff_strategy,initial_delay_ms,max_delay_ms,jitter_ratio,
  retryable_error_classes,active,source_reference,notes
)
select p.id,i.id,c.code,'sandbox',2,5000,'exponential',100,1000,0.000,
       array['timeout','transport','vendor_temporary'],true,
       'PracticeCtrl internal sandbox policy',
       'Deterministic sandbox retry policy. Not applicable to external production vendors.'
from public.integration_provider p
join public.integration_interface i on i.provider_id=p.id
cross join public.integration_capability_catalog c
where p.slug='practicectrl-sandbox'
  and i.name='PracticeCtrl deterministic sandbox'
  and c.code in (
    'member_validation','family_validation','benefit_check','authorisation_rule_check',
    'claim_submit','claim_response','claim_amend','claim_reverse','era_receive'
  )
on conflict (provider_id,interface_id,capability_code,environment) do update set
  max_attempts=excluded.max_attempts,
  timeout_ms=excluded.timeout_ms,
  initial_delay_ms=excluded.initial_delay_ms,
  max_delay_ms=excluded.max_delay_ms,
  jitter_ratio=excluded.jitter_ratio,
  retryable_error_classes=excluded.retryable_error_classes,
  active=true,
  notes=excluded.notes,
  updated_at=now();

commit;
