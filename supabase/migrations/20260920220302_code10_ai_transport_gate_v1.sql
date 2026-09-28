
begin;
alter table public.code10_ai_provider_config
  add column if not exists transport_ready boolean not null default false;

alter table public.code10_ai_provider_config
  drop constraint if exists code10_ai_enable_guard_ck;

alter table public.code10_ai_provider_config
  add constraint code10_ai_enable_guard_ck check (
    not enabled or (
      phi_approved
      and transport_ready
      and reviewed_at is not null
      and reviewed_by is not null
    )
  );

grant select(transport_ready) on public.code10_ai_provider_config to authenticated;
commit;
