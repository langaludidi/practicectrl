-- Phase 6 integration SQL: clinician workflow, immutable coding decisions,
-- confidentiality events, and server-side confirmation guardrails.
begin;

create table if not exists public.coding_session (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null,
  patient_id uuid,
  encounter_id uuid,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  service_date date not null,
  patient_sex public.coding_gender_rule,
  mit_release_id uuid not null references public.coding_source_release(id) on delete restrict,
  phisc_release_id uuid references public.coding_source_release(id) on delete restrict,
  cms_release_id uuid references public.coding_source_release(id) on delete restrict,
  source_context_hash text,
  status text not null default 'open' check (status in ('open','completed','cancelled')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint coding_session_completed_ck check (
    status = 'open' or completed_at is not null
  )
);

create index if not exists coding_session_practice_time_idx
  on public.coding_session(practice_id, started_at desc);
create index if not exists coding_session_encounter_idx
  on public.coding_session(encounter_id) where encounter_id is not null;
create index if not exists coding_session_patient_idx
  on public.coding_session(patient_id) where patient_id is not null;

create table if not exists public.coding_candidate_snapshot (
  id uuid primary key default gen_random_uuid(),
  coding_session_id uuid not null references public.coding_session(id) on delete restrict,
  practice_id uuid not null,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  code_id uuid not null references public.sa_icd10_code(id) on delete restrict,
  rank integer not null check (rank > 0),
  match_reason text not null,
  relevance double precision,
  warning_snapshot jsonb not null default '[]'::jsonb,
  pmb_snapshot jsonb not null default '{}'::jsonb,
  source_release_ids jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists coding_candidate_snapshot_session_idx
  on public.coding_candidate_snapshot(coding_session_id, rank, created_at);

create table if not exists public.coding_decision (
  id uuid primary key default gen_random_uuid(),
  coding_session_id uuid not null references public.coding_session(id) on delete restrict,
  practice_id uuid not null,
  code_id uuid not null references public.sa_icd10_code(id) on delete restrict,
  decision text not null check (decision in ('ACCEPTED','REJECTED','MANUALLY_SELECTED','REPLACED','REMOVED')),
  position text not null check (position in ('primary','secondary')),
  sequence_no integer not null default 1 check (sequence_no > 0),
  decision_reason text,
  selected_by uuid not null references auth.users(id) on delete restrict,
  selected_at timestamptz not null default now()
);

create index if not exists coding_decision_session_time_idx
  on public.coding_decision(coding_session_id, selected_at desc);
create index if not exists coding_decision_practice_time_idx
  on public.coding_decision(practice_id, selected_at desc);

create table if not exists public.coding_confidentiality_event (
  id uuid primary key default gen_random_uuid(),
  coding_session_id uuid references public.coding_session(id) on delete restrict,
  practice_id uuid not null,
  patient_id uuid,
  encounter_id uuid,
  request_type text not null check (request_type in ('patient_refusal','provider_refusal')),
  information_explained boolean not null default false,
  financial_implications_explained boolean not null default false,
  consent_or_instruction_recorded boolean not null default false,
  supporting_note_reference text,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists coding_confidentiality_practice_time_idx
  on public.coding_confidentiality_event(practice_id, created_at desc);

alter table public.coding_validation_event
  add column if not exists coding_session_id uuid references public.coding_session(id) on delete restrict;
create index if not exists coding_validation_session_idx
  on public.coding_validation_event(coding_session_id, triggered_at desc)
  where coding_session_id is not null;

alter table public.pmb_review
  drop constraint if exists pmb_review_coding_session_id_fkey;
alter table public.pmb_review
  add constraint pmb_review_coding_session_id_fkey
  foreign key (coding_session_id) references public.coding_session(id) on delete restrict;

alter table public.coding_session enable row level security;
alter table public.coding_candidate_snapshot enable row level security;
alter table public.coding_decision enable row level security;
alter table public.coding_confidentiality_event enable row level security;

revoke all on table public.coding_session from anon, authenticated;
revoke all on table public.coding_candidate_snapshot from anon, authenticated;
revoke all on table public.coding_decision from anon, authenticated;
revoke all on table public.coding_confidentiality_event from anon, authenticated;

grant select, insert on table public.coding_session to authenticated;
grant update (status, completed_at) on table public.coding_session to authenticated;
grant select, insert on table public.coding_candidate_snapshot to authenticated;
grant select, insert on table public.coding_decision to authenticated;
grant select, insert on table public.coding_confidentiality_event to authenticated;

revoke update on table public.coding_validation_event from authenticated;
grant update (status, resolved_at, resolved_by, resolution_action, override_reason)
  on table public.coding_validation_event to authenticated;

revoke update on table public.pmb_review from authenticated;
grant update (status, rationale, reviewed_by, reviewed_at)
  on table public.pmb_review to authenticated;

revoke update on table public.coding_ai_interaction from authenticated;
grant update (status, extracted_concepts, error_code, completed_at)
  on table public.coding_ai_interaction to authenticated;

drop policy if exists coding_session_member_read on public.coding_session;
create policy coding_session_member_read
on public.coding_session for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_session.practice_id
    and m.active = true
));

drop policy if exists coding_session_member_insert on public.coding_session;
create policy coding_session_member_insert
on public.coding_session for insert
to authenticated
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_session.practice_id
      and m.active = true
  )
);

drop policy if exists coding_session_actor_update on public.coding_session;
create policy coding_session_actor_update
on public.coding_session for update
to authenticated
using (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_session.practice_id
      and m.active = true
  )
)
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_session.practice_id
      and m.active = true
  )
);

drop policy if exists coding_candidate_member_read on public.coding_candidate_snapshot;
create policy coding_candidate_member_read
on public.coding_candidate_snapshot for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_candidate_snapshot.practice_id
    and m.active = true
));

drop policy if exists coding_candidate_actor_insert on public.coding_candidate_snapshot;
create policy coding_candidate_actor_insert
on public.coding_candidate_snapshot for insert
to authenticated
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.coding_session s
    where s.id = coding_candidate_snapshot.coding_session_id
      and s.practice_id = coding_candidate_snapshot.practice_id
      and s.status = 'open'
  )
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_candidate_snapshot.practice_id
      and m.active = true
  )
);

drop policy if exists coding_decision_member_read on public.coding_decision;
create policy coding_decision_member_read
on public.coding_decision for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_decision.practice_id
    and m.active = true
));

drop policy if exists coding_decision_practitioner_insert on public.coding_decision;
create policy coding_decision_practitioner_insert
on public.coding_decision for insert
to authenticated
with check (
  selected_by = (select auth.uid())
  and exists (
    select 1 from public.coding_session s
    where s.id = coding_decision.coding_session_id
      and s.practice_id = coding_decision.practice_id
      and s.status = 'open'
  )
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_decision.practice_id
      and m.active = true
      and m.role = 'practitioner'
  )
);

drop policy if exists coding_confidentiality_member_read on public.coding_confidentiality_event;
create policy coding_confidentiality_member_read
on public.coding_confidentiality_event for select
to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id = (select auth.uid())
    and m.practice_id = coding_confidentiality_event.practice_id
    and m.active = true
));

drop policy if exists coding_confidentiality_practitioner_insert on public.coding_confidentiality_event;
create policy coding_confidentiality_practitioner_insert
on public.coding_confidentiality_event for insert
to authenticated
with check (
  actor_user_id = (select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.practice_id = coding_confidentiality_event.practice_id
      and m.active = true
      and m.role = 'practitioner'
  )
);

create or replace function public.confirm_coding_decision(
  p_coding_session_id uuid,
  p_code_id uuid,
  p_position text,
  p_sequence_no integer default 1,
  p_decision text default 'ACCEPTED',
  p_decision_reason text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_session public.coding_session%rowtype;
  v_code public.sa_icd10_code%rowtype;
  v_decision_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_position not in ('primary','secondary') then
    raise exception 'Invalid code position';
  end if;
  if p_sequence_no is null or p_sequence_no < 1 then
    raise exception 'Invalid sequence number';
  end if;
  if p_decision not in ('ACCEPTED','MANUALLY_SELECTED','REPLACED') then
    raise exception 'This RPC only confirms positive coding decisions';
  end if;

  select * into v_session
  from public.coding_session
  where id = p_coding_session_id;

  if not found then
    raise exception 'Coding session not found or not accessible';
  end if;
  if v_session.status <> 'open' then
    raise exception 'Coding session is not open';
  end if;

  select * into v_code
  from public.sa_icd10_code
  where id = p_code_id
    and source_release_id = v_session.mit_release_id;

  if not found then
    raise exception 'ICD-10 code is not part of the session MIT release';
  end if;
  if not v_code.valid_clinical_use then
    raise exception 'ICD-10 code is not valid for clinical use';
  end if;
  if p_position = 'primary' and not v_code.valid_primary then
    raise exception 'ICD-10 code is not valid in the primary position';
  end if;
  if v_code.sa_start_date is not null and v_session.service_date < v_code.sa_start_date then
    raise exception 'ICD-10 code was not yet effective on the service date';
  end if;
  if v_code.sa_end_date is not null and v_session.service_date > v_code.sa_end_date then
    raise exception 'ICD-10 code was no longer effective on the service date';
  end if;

  if exists (
    select 1
    from public.coding_validation_event e
    where e.coding_session_id = p_coding_session_id
      and e.code_id = p_code_id
      and e.severity = 'BLOCKING'
      and e.status in ('open','acknowledged')
  ) then
    raise exception 'Unresolved blocking coding validation exists';
  end if;

  insert into public.coding_decision (
    coding_session_id,
    practice_id,
    code_id,
    decision,
    position,
    sequence_no,
    decision_reason,
    selected_by
  ) values (
    p_coding_session_id,
    v_session.practice_id,
    p_code_id,
    p_decision,
    p_position,
    p_sequence_no,
    p_decision_reason,
    (select auth.uid())
  )
  returning id into v_decision_id;

  insert into public.coding_audit_event (
    practice_id,
    actor_user_id,
    actor_role,
    event_type,
    entity_type,
    entity_id,
    source_release_ids,
    metadata
  ) values (
    v_session.practice_id,
    (select auth.uid()),
    'practitioner',
    'CODE_SELECTED',
    'coding_decision',
    v_decision_id,
    jsonb_strip_nulls(jsonb_build_object(
      'mit_release_id', v_session.mit_release_id,
      'phisc_release_id', v_session.phisc_release_id,
      'cms_release_id', v_session.cms_release_id
    )),
    jsonb_build_object(
      'coding_session_id', p_coding_session_id,
      'code_id', p_code_id,
      'code', v_code.code,
      'position', p_position,
      'sequence_no', p_sequence_no,
      'decision', p_decision
    )
  );

  return v_decision_id;
end;
$$;

revoke all on function public.confirm_coding_decision(uuid, uuid, text, integer, text, text)
  from public, anon;
grant execute on function public.confirm_coding_decision(uuid, uuid, text, integer, text, text)
  to authenticated;

commit;
