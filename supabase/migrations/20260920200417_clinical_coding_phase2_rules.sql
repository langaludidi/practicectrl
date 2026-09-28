-- Phase 2 integration SQL: deterministic coding-rule registry and validation events.
begin;

create table if not exists public.coding_rule (
  id uuid primary key default gen_random_uuid(),
  source_release_id uuid references public.coding_source_release(id) on delete restrict,
  rule_code text not null,
  title text not null,
  description text not null,
  rule_type text not null,
  severity text not null check (severity in ('INFO','ADVISORY','WARNING','BLOCKING')),
  authority public.coding_source_authority not null,
  source_reference text,
  effective_from date,
  effective_to date,
  machine_executable boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint coding_rule_version_unique unique (source_release_id, rule_code),
  constraint coding_rule_dates_ck check (effective_to is null or effective_from is null or effective_to >= effective_from)
);

create table if not exists public.coding_validation_event (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  encounter_id uuid,
  code_id uuid not null references public.sa_icd10_code(id) on delete restrict,
  coding_rule_id uuid references public.coding_rule(id) on delete restrict,
  rule_code text not null,
  severity text not null check (severity in ('INFO','ADVISORY','WARNING','BLOCKING')),
  message text not null,
  status text not null default 'open' check (status in ('open','acknowledged','resolved','overridden')),
  triggered_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete restrict,
  resolution_action text,
  override_reason text,
  source_context jsonb not null default '{}'::jsonb,
  constraint coding_validation_resolution_ck check (
    status not in ('resolved','overridden')
    or (resolved_at is not null and resolved_by is not null)
  ),
  constraint coding_validation_override_reason_ck check (
    status <> 'overridden' or length(trim(coalesce(override_reason,''))) > 0
  )
);

create index if not exists coding_rule_active_idx on public.coding_rule(active, rule_code);
create index if not exists coding_validation_practice_time_idx on public.coding_validation_event(practice_id, triggered_at desc);
create index if not exists coding_validation_code_idx on public.coding_validation_event(code_id, triggered_at desc);

alter table public.coding_rule enable row level security;
alter table public.coding_validation_event enable row level security;

revoke all on table public.coding_rule from anon, authenticated;
revoke all on table public.coding_validation_event from anon, authenticated;
grant select on table public.coding_rule to authenticated;
grant select, insert, update on table public.coding_validation_event to authenticated;

drop policy if exists coding_rule_member_read on public.coding_rule;
create policy coding_rule_member_read
on public.coding_rule for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid()) and m.active = true
));

drop policy if exists coding_validation_member_read on public.coding_validation_event;
create policy coding_validation_member_read
on public.coding_validation_event for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_validation_event.practice_id
    and m.active = true
));

drop policy if exists coding_validation_member_insert on public.coding_validation_event;
create policy coding_validation_member_insert
on public.coding_validation_event for insert
to authenticated
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_validation_event.practice_id
      and m.active = true
  )
);

drop policy if exists coding_validation_member_update on public.coding_validation_event;
create policy coding_validation_member_update
on public.coding_validation_event for update
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_validation_event.practice_id
    and m.active = true
))
with check (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_validation_event.practice_id
    and m.active = true
));

commit;
