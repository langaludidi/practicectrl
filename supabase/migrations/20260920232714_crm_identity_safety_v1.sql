
begin;

create table if not exists public.crm_patient_match_candidate (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_a_id uuid not null references public.crm_patient(id) on delete cascade,
  patient_b_id uuid not null references public.crm_patient(id) on delete cascade,
  match_score numeric(5,4) not null check (match_score between 0 and 1),
  match_reasons text[] not null default '{}',
  status text not null default 'pending' check (status in ('pending','same_person','not_same_person','deferred','superseded')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  constraint crm_match_not_self_ck check (patient_a_id <> patient_b_id),
  constraint crm_match_order_ck check (patient_a_id::text < patient_b_id::text),
  unique(practice_id,patient_a_id,patient_b_id)
);
create index if not exists crm_patient_match_queue_idx on public.crm_patient_match_candidate(practice_id,status,match_score desc);
create index if not exists crm_patient_match_reviewed_by_idx on public.crm_patient_match_candidate(reviewed_by) where reviewed_by is not null;

create table if not exists public.crm_patient_identity_conflict (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid not null references public.crm_patient(id) on delete cascade,
  field_name text not null,
  current_value text,
  incoming_value text,
  source_system text not null,
  source_reference text,
  status text not null default 'open' check (status in ('open','accepted_current','accepted_incoming','resolved_other')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists crm_identity_conflict_queue_idx on public.crm_patient_identity_conflict(practice_id,status,created_at);
create index if not exists crm_identity_conflict_patient_idx on public.crm_patient_identity_conflict(patient_id,status);
create index if not exists crm_identity_conflict_reviewed_by_idx on public.crm_patient_identity_conflict(reviewed_by) where reviewed_by is not null;

alter table public.crm_patient_match_candidate enable row level security;
alter table public.crm_patient_identity_conflict enable row level security;
revoke all on table public.crm_patient_match_candidate from anon,authenticated;
revoke all on table public.crm_patient_identity_conflict from anon,authenticated;
grant select,update on table public.crm_patient_match_candidate to authenticated;
grant select,update on table public.crm_patient_identity_conflict to authenticated;

create policy crm_match_staff_read on public.crm_patient_match_candidate for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_match_candidate.practice_id and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin','auditor')
));
create policy crm_match_privileged_update on public.crm_patient_match_candidate for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_match_candidate.practice_id and m.active
    and m.role in ('practice_manager','clinical_admin','system_admin')
))
with check (((select auth.jwt())->>'aal')='aal2' and reviewed_by=(select auth.uid()) and reviewed_at is not null and exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_match_candidate.practice_id and m.active
    and m.role in ('practice_manager','clinical_admin','system_admin')
));

create policy crm_conflict_staff_read on public.crm_patient_identity_conflict for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_identity_conflict.practice_id and m.active
));
create policy crm_conflict_privileged_update on public.crm_patient_identity_conflict for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_identity_conflict.practice_id and m.active
    and m.role in ('practitioner','practice_manager','clinical_admin','system_admin')
))
with check (((select auth.jwt())->>'aal')='aal2' and reviewed_by=(select auth.uid()) and reviewed_at is not null and exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_identity_conflict.practice_id and m.active
    and m.role in ('practitioner','practice_manager','clinical_admin','system_admin')
));

create or replace function public.refresh_crm_match_candidates(p_practice_id uuid)
returns integer
language plpgsql
volatile
security invoker
set search_path=public,extensions,pg_temp
as $$
declare
  v_count integer := 0;
begin
  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=p_practice_id and m.active
      and m.role in ('practice_manager','clinical_admin','system_admin')
  ) then raise exception 'Privileged CRM role required'; end if;

  insert into public.crm_patient_match_candidate(
    practice_id,patient_a_id,patient_b_id,match_score,match_reasons
  )
  select p_practice_id,a.id,b.id,
    greatest(
      case when a.date_of_birth is not null and a.date_of_birth=b.date_of_birth
             and lower(coalesce(a.first_name,''))=lower(coalesce(b.first_name,''))
             and lower(coalesce(a.last_name,''))=lower(coalesce(b.last_name,'')) then 0.98 else 0 end,
      case when a.primary_email is not null and lower(a.primary_email)=lower(b.primary_email) then 0.94 else 0 end,
      case when a.primary_phone is not null and regexp_replace(a.primary_phone,'\D','','g')=regexp_replace(b.primary_phone,'\D','','g') then 0.92 else 0 end,
      extensions.similarity(lower(a.display_name),lower(b.display_name)) * 0.70
    ),
    array_remove(array[
      case when a.date_of_birth is not null and a.date_of_birth=b.date_of_birth then 'same date of birth' end,
      case when a.primary_email is not null and lower(a.primary_email)=lower(b.primary_email) then 'same email' end,
      case when a.primary_phone is not null and regexp_replace(a.primary_phone,'\D','','g')=regexp_replace(b.primary_phone,'\D','','g') then 'same phone' end,
      case when extensions.similarity(lower(a.display_name),lower(b.display_name))>=0.80 then 'similar name' end
    ],null)
  from public.crm_patient a
  join public.crm_patient b
    on b.practice_id=a.practice_id and a.id::text<b.id::text
  where a.practice_id=p_practice_id
    and a.status<>'merged' and b.status<>'merged'
    and (
      (a.date_of_birth is not null and a.date_of_birth=b.date_of_birth and lower(coalesce(a.last_name,''))=lower(coalesce(b.last_name,'')))
      or (a.primary_email is not null and lower(a.primary_email)=lower(b.primary_email))
      or (a.primary_phone is not null and regexp_replace(a.primary_phone,'\D','','g')=regexp_replace(b.primary_phone,'\D','','g'))
      or extensions.similarity(lower(a.display_name),lower(b.display_name))>=0.86
    )
  on conflict(practice_id,patient_a_id,patient_b_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.refresh_crm_match_candidates(uuid) from public,anon;
grant execute on function public.refresh_crm_match_candidates(uuid) to authenticated;

commit;
