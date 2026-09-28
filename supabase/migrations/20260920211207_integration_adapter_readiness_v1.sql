
begin;

create table if not exists public.integration_adapter_capability (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete cascade,
  interface_id uuid not null references public.integration_interface(id) on delete cascade,
  capability_code text not null references public.integration_capability_catalog(code) on delete restrict,
  implementation_status text not null default 'not_started'
    check (implementation_status in (
      'not_started','spec_received','mapping','sandbox_ready',
      'conformance_passed','accredited','production_ready'
    )),
  executable_sandbox boolean not null default false,
  executable_production boolean not null default false,
  suite_version text not null default '1',
  last_conformance_at timestamptz,
  conformance_result jsonb,
  notes text,
  updated_at timestamptz not null default now(),
  unique(provider_id,interface_id,capability_code),
  constraint adapter_production_requires_readiness_ck check (
    not executable_production or implementation_status in ('accredited','production_ready')
  ),
  constraint adapter_sandbox_requires_readiness_ck check (
    not executable_sandbox or implementation_status in ('sandbox_ready','conformance_passed','accredited','production_ready')
  )
);

create index if not exists integration_adapter_capability_provider_idx
  on public.integration_adapter_capability(provider_id,implementation_status);
create index if not exists integration_adapter_capability_interface_idx
  on public.integration_adapter_capability(interface_id,capability_code);

alter table public.integration_adapter_capability enable row level security;
revoke all on table public.integration_adapter_capability from anon, authenticated;
grant select on table public.integration_adapter_capability to authenticated;

drop policy if exists integration_adapter_capability_staff_read on public.integration_adapter_capability;
create policy integration_adapter_capability_staff_read
on public.integration_adapter_capability for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

insert into public.integration_adapter_capability
(provider_id,interface_id,capability_code,implementation_status,executable_sandbox,executable_production,notes)
select c.provider_id,c.interface_id,c.capability_code,'not_started',false,false,
       'Provider capability is recorded in the Integration Registry, but the PracticeCtrl adapter intentionally remains non-executable until the official specification is implemented and conformance-tested.'
from public.integration_capability c
join public.integration_provider p on p.id=c.provider_id
where p.slug in ('medikredit','altron-switchon')
  and c.interface_id is not null
on conflict (provider_id,interface_id,capability_code) do nothing;

commit;
