create table public.clinical_note (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  patient_id uuid not null references public.crm_patient(id) on delete restrict,
  encounter_id uuid not null references public.practice_encounter(id) on delete restrict,
  note_type text not null default 'consultation' check (note_type in ('consultation','progress','procedure','telephone','review','other')),
  title text,
  subjective text,
  objective text,
  assessment text,
  plan text,
  narrative text,
  structured_data jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','signed','amended','void')),
  amendment_of_note_id uuid references public.clinical_note(id) on delete restrict,
  author_user_id uuid not null references auth.users(id) on delete restrict,
  signed_by uuid references auth.users(id) on delete restrict,
  signed_at timestamptz,
  content_sha256 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clinical_note_signature_ck check (
    (status='draft' and signed_by is null and signed_at is null and content_sha256 is null)
    or (status in ('signed','amended') and signed_by is not null and signed_at is not null and content_sha256 is not null)
    or status='void'
  )
);
create index clinical_note_practice_patient_idx on public.clinical_note(practice_id,patient_id,created_at desc);
create index clinical_note_encounter_idx on public.clinical_note(encounter_id,created_at desc);
create index clinical_note_author_idx on public.clinical_note(author_user_id,created_at desc);
create index clinical_note_amendment_idx on public.clinical_note(amendment_of_note_id) where amendment_of_note_id is not null;

create table public.clinical_note_diagnosis (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  note_id uuid not null references public.clinical_note(id) on delete cascade,
  coding_decision_id uuid references public.coding_decision(id) on delete restrict,
  code_system text not null default 'ICD-10',
  code text not null,
  normalized_code text not null,
  description_snapshot text not null,
  position text not null default 'secondary' check (position in ('primary','secondary','external_cause','manifestation')),
  source text not null default 'Code10',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(note_id,normalized_code,position)
);
create index clinical_note_diagnosis_practice_idx on public.clinical_note_diagnosis(practice_id,note_id);
create index clinical_note_diagnosis_decision_idx on public.clinical_note_diagnosis(coding_decision_id) where coding_decision_id is not null;

create table public.clinical_observation (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  patient_id uuid not null references public.crm_patient(id) on delete restrict,
  encounter_id uuid not null references public.practice_encounter(id) on delete restrict,
  observation_type text not null,
  code_system text,
  code text,
  value_numeric numeric,
  value_text text,
  unit text,
  observed_at timestamptz not null default now(),
  recorded_by uuid not null references auth.users(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint clinical_observation_value_ck check (value_numeric is not null or nullif(trim(coalesce(value_text,'')),'') is not null)
);
create index clinical_observation_patient_idx on public.clinical_observation(practice_id,patient_id,observed_at desc);
create index clinical_observation_encounter_idx on public.clinical_observation(encounter_id,observed_at desc);
create index clinical_observation_recorded_by_idx on public.clinical_observation(recorded_by);

create table public.clinical_note_event (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.clinical_note(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index clinical_note_event_note_idx on public.clinical_note_event(note_id,created_at desc);
create index clinical_note_event_actor_idx on public.clinical_note_event(actor_user_id) where actor_user_id is not null;

alter table public.clinical_note enable row level security;
alter table public.clinical_note_diagnosis enable row level security;
alter table public.clinical_observation enable row level security;
alter table public.clinical_note_event enable row level security;

revoke all on public.clinical_note, public.clinical_note_diagnosis, public.clinical_observation, public.clinical_note_event from anon, authenticated;
grant select,insert,update on public.clinical_note to authenticated;
grant select,insert,delete on public.clinical_note_diagnosis to authenticated;
grant select,insert on public.clinical_observation to authenticated;
grant select,insert on public.clinical_note_event to authenticated;

create policy clinical_note_read on public.clinical_note for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=clinical_note.practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor'))
);
create policy clinical_note_insert on public.clinical_note for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and author_user_id=(select auth.uid()) and status='draft'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=clinical_note.practice_id and m.active and m.role in ('practitioner','clinical_admin'))
);
create policy clinical_note_update on public.clinical_note for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2' and status='draft'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=clinical_note.practice_id and m.active and m.role in ('practitioner','clinical_admin'))
  and (
    author_user_id=(select auth.uid())
    or exists(select 1 from public.practice_encounter e where e.id=clinical_note.encounter_id and e.practitioner_user_id=(select auth.uid()))
  )
) with check (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=clinical_note.practice_id and m.active and m.role in ('practitioner','clinical_admin'))
);

create policy clinical_note_diagnosis_read on public.clinical_note_diagnosis for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=clinical_note_diagnosis.practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor'))
);
create policy clinical_note_diagnosis_insert on public.clinical_note_diagnosis for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid())
  and exists(select 1 from public.clinical_note n join public.practice_staff_member m on m.practice_id=n.practice_id where n.id=clinical_note_diagnosis.note_id and n.practice_id=clinical_note_diagnosis.practice_id and n.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('practitioner','clinical_admin'))
);
create policy clinical_note_diagnosis_delete on public.clinical_note_diagnosis for delete to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.clinical_note n join public.practice_staff_member m on m.practice_id=n.practice_id where n.id=clinical_note_diagnosis.note_id and n.status='draft' and m.user_id=(select auth.uid()) and m.active and m.role in ('practitioner','clinical_admin'))
);

create policy clinical_observation_read on public.clinical_observation for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=clinical_observation.practice_id and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor'))
);
create policy clinical_observation_insert on public.clinical_observation for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and recorded_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=clinical_observation.practice_id and m.active and m.role in ('practitioner','clinical_admin'))
);

create policy clinical_note_event_read on public.clinical_note_event for select to authenticated using (
  exists(select 1 from public.clinical_note n join public.practice_staff_member m on m.practice_id=n.practice_id where n.id=clinical_note_event.note_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor'))
);
create policy clinical_note_event_insert on public.clinical_note_event for insert to authenticated with check (
  actor_user_id=(select auth.uid()) and exists(select 1 from public.clinical_note n join public.practice_staff_member m on m.practice_id=n.practice_id where n.id=clinical_note_event.note_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practitioner','clinical_admin'))
);
