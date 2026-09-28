-- Phase 5 integration SQL: AI-assist governance metadata.
-- Raw clinical narrative is intentionally NOT stored in this table.

begin;

create table if not exists public.coding_ai_interaction (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  encounter_id uuid,
  provider text not null,
  model_id text not null,
  purpose text not null default 'clinical_concept_extraction',
  input_sha256 text not null,
  input_char_count integer not null check (input_char_count >= 0),
  extracted_concepts jsonb,
  status text not null check (status in ('started','completed','failed','discarded')),
  error_code text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint coding_ai_completed_ck check (
    status not in ('completed','failed','discarded') or completed_at is not null
  )
);

create index if not exists coding_ai_interaction_practice_time_idx
  on public.coding_ai_interaction(practice_id, started_at desc);

alter table public.coding_ai_interaction enable row level security;
revoke all on table public.coding_ai_interaction from anon, authenticated;
grant select, insert, update on table public.coding_ai_interaction to authenticated;

drop policy if exists coding_ai_member_read on public.coding_ai_interaction;
create policy coding_ai_member_read
on public.coding_ai_interaction for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_ai_interaction.practice_id
    and m.active = true
));

drop policy if exists coding_ai_member_insert on public.coding_ai_interaction;
create policy coding_ai_member_insert
on public.coding_ai_interaction for insert
to authenticated
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_ai_interaction.practice_id
      and m.active = true
  )
);

drop policy if exists coding_ai_member_update on public.coding_ai_interaction;
create policy coding_ai_member_update
on public.coding_ai_interaction for update
to authenticated
using (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_ai_interaction.practice_id
      and m.active = true
  )
)
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_ai_interaction.practice_id
      and m.active = true
  )
);

commit;
