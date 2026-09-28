
begin;

create table if not exists public.crm_patient_scheme_membership (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid not null references public.crm_patient(id) on delete cascade,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  medical_scheme_option_id uuid references public.medical_scheme_option(id) on delete restrict,
  scheme_name_snapshot text not null,
  option_name_snapshot text,
  member_number_masked text not null,
  member_number_secret_id uuid not null,
  dependant_code text,
  membership_status text not null default 'unverified'
    check (membership_status in ('unverified','active_verified','inactive_verified','needs_review')),
  effective_from date,
  effective_to date,
  verification_source text,
  verified_at timestamptz,
  source_system text not null default 'PracticeCtrl',
  source_reference text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_scheme_membership_dates_ck check (
    effective_to is null or effective_from is null or effective_to>=effective_from
  )
);
create index if not exists crm_scheme_membership_patient_idx
  on public.crm_patient_scheme_membership(patient_id,membership_status,created_at desc);
create index if not exists crm_scheme_membership_scheme_idx
  on public.crm_patient_scheme_membership(medical_scheme_id,membership_status)
  where medical_scheme_id is not null;
create index if not exists crm_scheme_membership_created_by_idx
  on public.crm_patient_scheme_membership(created_by)
  where created_by is not null;
create index if not exists crm_scheme_membership_updated_by_idx
  on public.crm_patient_scheme_membership(updated_by)
  where updated_by is not null;

alter table public.crm_patient_scheme_membership enable row level security;
revoke all on table public.crm_patient_scheme_membership from anon,authenticated;

grant select(
  id,practice_id,patient_id,medical_scheme_id,medical_scheme_option_id,
  scheme_name_snapshot,option_name_snapshot,member_number_masked,dependant_code,
  membership_status,effective_from,effective_to,verification_source,verified_at,
  source_system,source_reference,created_at,updated_at
) on public.crm_patient_scheme_membership to authenticated;

create policy crm_scheme_membership_staff_read
on public.crm_patient_scheme_membership for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid())
    and m.practice_id=crm_patient_scheme_membership.practice_id
    and m.active
));

create or replace function public.mask_member_number(p_member_number text)
returns text
language sql
immutable
security invoker
set search_path=public,pg_temp
as $$
  select case
    when length(regexp_replace(coalesce(p_member_number,''),'\s','','g'))<=4
      then repeat('•',greatest(length(regexp_replace(coalesce(p_member_number,''),'\s','','g'))-1,0))
           || right(regexp_replace(coalesce(p_member_number,''),'\s','','g'),1)
    else repeat('•',greatest(length(regexp_replace(coalesce(p_member_number,''),'\s','','g'))-4,4))
         || right(regexp_replace(coalesce(p_member_number,''),'\s','','g'),4)
  end;
$$;
revoke all on function public.mask_member_number(text) from public,anon,authenticated;
grant execute on function public.mask_member_number(text) to service_role;

create or replace function public.upsert_patient_scheme_membership(
  p_membership_id uuid,
  p_practice_id uuid,
  p_patient_id uuid,
  p_scheme_name text,
  p_option_name text,
  p_member_number text,
  p_dependant_code text,
  p_medical_scheme_id uuid default null,
  p_medical_scheme_option_id uuid default null,
  p_source_system text default 'PracticeCtrl',
  p_source_reference text default null,
  p_actor_user_id uuid default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,vault,pg_temp
as $$
declare
  v_id uuid := coalesce(p_membership_id,gen_random_uuid());
  v_secret_id uuid;
  v_secret_name text;
  v_existing public.crm_patient_scheme_membership%rowtype;
begin
  if length(trim(coalesce(p_member_number,'')))<2 then
    raise exception 'Member number is required';
  end if;
  if length(trim(coalesce(p_scheme_name,'')))<2 then
    raise exception 'Scheme name is required';
  end if;
  if not exists (
    select 1 from public.crm_patient
    where id=p_patient_id and practice_id=p_practice_id
  ) then raise exception 'Patient is not in this practice'; end if;

  if p_medical_scheme_option_id is not null and not exists (
    select 1 from public.medical_scheme_option o
    where o.id=p_medical_scheme_option_id
      and (p_medical_scheme_id is null or o.medical_scheme_id=p_medical_scheme_id)
  ) then raise exception 'Scheme option does not match the scheme'; end if;

  select * into v_existing
  from public.crm_patient_scheme_membership
  where id=v_id
  for update;

  v_secret_name := 'practicectrl/member/' || v_id::text;

  if found then
    if v_existing.practice_id<>p_practice_id or v_existing.patient_id<>p_patient_id then
      raise exception 'Membership identity cannot be reassigned';
    end if;
    v_secret_id := v_existing.member_number_secret_id;
    perform vault.update_secret(
      v_secret_id,
      trim(p_member_number),
      v_secret_name,
      'PracticeCtrl encrypted medical-scheme member number',
      null
    );

    update public.crm_patient_scheme_membership
    set medical_scheme_id=p_medical_scheme_id,
        medical_scheme_option_id=p_medical_scheme_option_id,
        scheme_name_snapshot=trim(p_scheme_name),
        option_name_snapshot=nullif(trim(coalesce(p_option_name,'')),''),
        member_number_masked=public.mask_member_number(trim(p_member_number)),
        dependant_code=nullif(trim(coalesce(p_dependant_code,'')),''),
        membership_status='unverified',
        verification_source=null,
        verified_at=null,
        source_system=coalesce(nullif(trim(p_source_system),''),'PracticeCtrl'),
        source_reference=p_source_reference,
        updated_by=p_actor_user_id,
        updated_at=now()
    where id=v_id;
  else
    v_secret_id := vault.create_secret(
      trim(p_member_number),
      v_secret_name,
      'PracticeCtrl encrypted medical-scheme member number',
      null
    );

    insert into public.crm_patient_scheme_membership(
      id,practice_id,patient_id,medical_scheme_id,medical_scheme_option_id,
      scheme_name_snapshot,option_name_snapshot,member_number_masked,
      member_number_secret_id,dependant_code,membership_status,
      source_system,source_reference,created_by,updated_by
    ) values(
      v_id,p_practice_id,p_patient_id,p_medical_scheme_id,p_medical_scheme_option_id,
      trim(p_scheme_name),nullif(trim(coalesce(p_option_name,'')),''),
      public.mask_member_number(trim(p_member_number)),v_secret_id,
      nullif(trim(coalesce(p_dependant_code,'')),''),
      'unverified',coalesce(nullif(trim(p_source_system),''),'PracticeCtrl'),
      p_source_reference,p_actor_user_id,p_actor_user_id
    );
  end if;

  return v_id;
end;
$$;

revoke all on function public.upsert_patient_scheme_membership(uuid,uuid,uuid,text,text,text,text,uuid,uuid,text,text,uuid)
  from public,anon,authenticated;
grant execute on function public.upsert_patient_scheme_membership(uuid,uuid,uuid,text,text,text,text,uuid,uuid,text,text,uuid)
  to service_role;

create or replace function public.get_patient_member_number_for_integration(
  p_membership_id uuid
)
returns text
language sql
stable
security invoker
set search_path=public,vault,pg_temp
as $$
  select v.decrypted_secret
  from public.crm_patient_scheme_membership m
  join vault.decrypted_secrets v on v.id=m.member_number_secret_id
  where m.id=p_membership_id;
$$;
revoke all on function public.get_patient_member_number_for_integration(uuid)
  from public,anon,authenticated;
grant execute on function public.get_patient_member_number_for_integration(uuid)
  to service_role;

commit;
