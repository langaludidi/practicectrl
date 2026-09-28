
begin;

create table if not exists public.practice_encounter (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid not null references public.crm_patient(id) on delete restrict,
  practitioner_user_id uuid references auth.users(id) on delete set null,
  service_date date not null,
  encounter_type text not null default 'consultation'
    check (encounter_type in ('consultation','procedure','follow_up','telehealth','hospital','other')),
  status text not null default 'open'
    check (status in ('open','completed','cancelled','imported')),
  external_pms_ref text,
  source_system text not null default 'PracticeCtrl',
  source_reference text,
  created_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(practice_id,source_system,source_reference)
);
create index if not exists practice_encounter_patient_idx
  on public.practice_encounter(patient_id,service_date desc);
create index if not exists practice_encounter_practice_idx
  on public.practice_encounter(practice_id,service_date desc,status);
create index if not exists practice_encounter_practitioner_idx
  on public.practice_encounter(practitioner_user_id,service_date desc)
  where practitioner_user_id is not null;
create index if not exists practice_encounter_created_by_idx
  on public.practice_encounter(created_by) where created_by is not null;

alter table public.practice_encounter enable row level security;
revoke all on table public.practice_encounter from anon,authenticated;
grant select,insert,update on table public.practice_encounter to authenticated;

create policy practice_encounter_staff_read
on public.practice_encounter for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.practice_id=practice_encounter.practice_id and m.active
));

create policy practice_encounter_clinical_insert
on public.practice_encounter for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=practice_encounter.practice_id and m.active
      and m.role in ('practitioner','clinical_admin','practice_manager','system_admin')
  )
);

create policy practice_encounter_clinical_update
on public.practice_encounter for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=practice_encounter.practice_id and m.active
      and m.role in ('practitioner','clinical_admin','practice_manager','system_admin')
  )
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=practice_encounter.practice_id and m.active
      and m.role in ('practitioner','clinical_admin','practice_manager','system_admin')
  )
);

alter table public.billing_invoice add column if not exists encounter_id uuid references public.practice_encounter(id) on delete restrict;
create index if not exists billing_invoice_encounter_idx on public.billing_invoice(encounter_id) where encounter_id is not null;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='coding_session_encounter_id_fkey') then
    alter table public.coding_session add constraint coding_session_encounter_id_fkey
      foreign key(encounter_id) references public.practice_encounter(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='claim_record_encounter_id_fkey') then
    alter table public.claim_record add constraint claim_record_encounter_id_fkey
      foreign key(encounter_id) references public.practice_encounter(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conname='payer_transaction_encounter_id_fkey') then
    alter table public.payer_transaction add constraint payer_transaction_encounter_id_fkey
      foreign key(encounter_id) references public.practice_encounter(id) on delete restrict;
  end if;
end $$;

create index if not exists claim_record_encounter_idx on public.claim_record(encounter_id) where encounter_id is not null;
create index if not exists payer_transaction_encounter_idx on public.payer_transaction(encounter_id) where encounter_id is not null;

create or replace function public.create_practice_encounter(
  p_practice_id uuid,
  p_patient_id uuid,
  p_service_date date,
  p_encounter_type text default 'consultation',
  p_external_pms_ref text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_role public.practice_staff_role;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_encounter_type not in ('consultation','procedure','follow_up','telehealth','hospital','other') then raise exception 'Invalid encounter type'; end if;
  if p_service_date is null then raise exception 'Service date is required'; end if;

  select role into v_role from public.practice_staff_member
  where user_id=v_user and practice_id=p_practice_id and active;
  if v_role not in ('practitioner','clinical_admin','practice_manager','system_admin') then
    raise exception 'Clinical encounter role required';
  end if;
  if not exists(select 1 from public.crm_patient where id=p_patient_id and practice_id=p_practice_id and status<>'merged') then
    raise exception 'Patient is not in this practice';
  end if;

  insert into public.practice_encounter(
    practice_id,patient_id,practitioner_user_id,service_date,encounter_type,
    external_pms_ref,source_system,created_by
  ) values(
    p_practice_id,p_patient_id,case when v_role='practitioner' then v_user else null end,
    p_service_date,p_encounter_type,nullif(trim(coalesce(p_external_pms_ref,'')),''),
    'PracticeCtrl',v_user
  ) returning id into v_id;

  insert into public.crm_timeline_event(
    practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system
  ) values(
    p_practice_id,p_patient_id,'note',now(),'Service encounter created',
    p_encounter_type||' · service date '||p_service_date::text,
    'practice_encounter',v_id,v_user,'PracticeCtrl'
  );

  return v_id;
end;
$$;
revoke all on function public.create_practice_encounter(uuid,uuid,date,text,text) from public,anon;
grant execute on function public.create_practice_encounter(uuid,uuid,date,text,text) to authenticated;

create or replace function public.complete_practice_encounter(p_encounter_id uuid)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_enc public.practice_encounter%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_enc from public.practice_encounter where id=p_encounter_id for update;
  if not found then raise exception 'Encounter not found or not accessible'; end if;
  if v_enc.status<>'open' then raise exception 'Only open encounters can be completed'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_enc.practice_id and m.active
      and m.role in ('practitioner','clinical_admin','practice_manager','system_admin')
  ) then raise exception 'Clinical encounter role required'; end if;

  update public.practice_encounter
  set status='completed',completed_at=now(),updated_at=now()
  where id=p_encounter_id;

  return p_encounter_id;
end;
$$;
revoke all on function public.complete_practice_encounter(uuid) from public,anon;
grant execute on function public.complete_practice_encounter(uuid) to authenticated;

commit;
