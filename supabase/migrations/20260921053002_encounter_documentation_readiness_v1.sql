
begin;

create table if not exists public.encounter_documentation_requirement (
  requirement_key text primary key,
  display_name text not null,
  description text not null,
  applies_to text[] not null default array['all']::text[],
  required_for_completion boolean not null default false,
  required_for_coding boolean not null default false,
  required_for_billing boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.encounter_documentation_status (
  encounter_id uuid not null references public.practice_encounter(id) on delete cascade,
  requirement_key text not null references public.encounter_documentation_requirement(requirement_key) on delete restrict,
  status text not null default 'missing'
    check (status in ('missing','documented','not_applicable')),
  attestation_note text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key(encounter_id,requirement_key),
  constraint encounter_doc_note_length_ck check (attestation_note is null or length(attestation_note)<=500)
);
create index if not exists encounter_documentation_updated_by_idx
  on public.encounter_documentation_status(updated_by) where updated_by is not null;

create table if not exists public.encounter_documentation_event (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid not null references public.practice_encounter(id) on delete cascade,
  requirement_key text not null,
  from_status text,
  to_status text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  note_present boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists encounter_documentation_event_encounter_idx
  on public.encounter_documentation_event(encounter_id,created_at desc);
create index if not exists encounter_documentation_event_actor_idx
  on public.encounter_documentation_event(actor_user_id) where actor_user_id is not null;

insert into public.encounter_documentation_requirement(
  requirement_key,display_name,description,applies_to,
  required_for_completion,required_for_coding,required_for_billing
) values
('service_reason','Reason for service documented','The clinical record identifies why the patient was seen.',array['all'],true,true,true),
('assessment','Clinical assessment documented','The clinician has documented an assessment appropriate to the service.',array['all'],true,true,true),
('diagnosis_specificity','Diagnosis documentation supports coding specificity','The documentation supports the specificity required for the selected diagnosis code.',array['all'],true,true,true),
('practitioner_signoff','Practitioner review completed','The treating/reviewing practitioner has reviewed the encounter documentation.',array['all'],true,true,true),
('procedure_detail','Procedure detail documented','The performed procedure and clinically relevant detail are documented.',array['procedure'],true,true,true),
('telehealth_context','Telehealth context documented','The record identifies that the service was delivered by telehealth and captures the relevant service context.',array['telehealth'],true,false,true),
('hospital_context','Hospital service context documented','The record contains the relevant hospital/admission/service context for coding and billing.',array['hospital'],true,true,true)
on conflict(requirement_key) do update set
  display_name=excluded.display_name,
  description=excluded.description,
  applies_to=excluded.applies_to,
  required_for_completion=excluded.required_for_completion,
  required_for_coding=excluded.required_for_coding,
  required_for_billing=excluded.required_for_billing,
  active=true;

alter table public.encounter_documentation_requirement enable row level security;
alter table public.encounter_documentation_status enable row level security;
alter table public.encounter_documentation_event enable row level security;

revoke all on table public.encounter_documentation_requirement from anon,authenticated;
revoke all on table public.encounter_documentation_status from anon,authenticated;
revoke all on table public.encounter_documentation_event from anon,authenticated;

grant select on table public.encounter_documentation_requirement to authenticated;
grant select,insert,update on table public.encounter_documentation_status to authenticated;
grant select on table public.encounter_documentation_event to authenticated;

create policy encounter_doc_requirement_staff_read
on public.encounter_documentation_requirement for select to authenticated
using (exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active));

create policy encounter_doc_status_staff_read
on public.encounter_documentation_status for select to authenticated
using (exists(
  select 1 from public.practice_encounter e
  join public.practice_staff_member m on m.practice_id=e.practice_id
  where e.id=encounter_documentation_status.encounter_id
    and m.user_id=(select auth.uid()) and m.active
));

create policy encounter_doc_status_practitioner_insert
on public.encounter_documentation_status for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and updated_by=(select auth.uid())
  and exists(
    select 1 from public.practice_encounter e
    join public.practice_staff_member m on m.practice_id=e.practice_id
    where e.id=encounter_documentation_status.encounter_id
      and m.user_id=(select auth.uid()) and m.active and m.role='practitioner'
  )
);

create policy encounter_doc_status_practitioner_update
on public.encounter_documentation_status for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(
    select 1 from public.practice_encounter e
    join public.practice_staff_member m on m.practice_id=e.practice_id
    where e.id=encounter_documentation_status.encounter_id
      and m.user_id=(select auth.uid()) and m.active and m.role='practitioner'
  )
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and updated_by=(select auth.uid())
  and exists(
    select 1 from public.practice_encounter e
    join public.practice_staff_member m on m.practice_id=e.practice_id
    where e.id=encounter_documentation_status.encounter_id
      and m.user_id=(select auth.uid()) and m.active and m.role='practitioner'
  )
);

create policy encounter_doc_event_staff_read
on public.encounter_documentation_event for select to authenticated
using (exists(
  select 1 from public.practice_encounter e
  join public.practice_staff_member m on m.practice_id=e.practice_id
  where e.id=encounter_documentation_event.encounter_id
    and m.user_id=(select auth.uid()) and m.active
));

create or replace function public.seed_encounter_documentation()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  insert into public.encounter_documentation_status(encounter_id,requirement_key,status,updated_by)
  select new.id,r.requirement_key,'missing',null
  from public.encounter_documentation_requirement r
  where r.active and ('all'=any(r.applies_to) or new.encounter_type=any(r.applies_to))
  on conflict(encounter_id,requirement_key) do nothing;
  return new;
end;
$$;
revoke all on function public.seed_encounter_documentation() from public,anon,authenticated;

drop trigger if exists trg_seed_encounter_documentation on public.practice_encounter;
create trigger trg_seed_encounter_documentation
after insert on public.practice_encounter
for each row execute function public.seed_encounter_documentation();

insert into public.encounter_documentation_status(encounter_id,requirement_key,status,updated_by)
select e.id,r.requirement_key,'missing',null
from public.practice_encounter e
join public.encounter_documentation_requirement r
  on r.active and ('all'=any(r.applies_to) or e.encounter_type=any(r.applies_to))
on conflict(encounter_id,requirement_key) do nothing;

create or replace function public.audit_encounter_documentation_change()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if tg_op='INSERT' then
    insert into public.encounter_documentation_event(
      encounter_id,requirement_key,from_status,to_status,actor_user_id,note_present
    ) values(
      new.encounter_id,new.requirement_key,null,new.status,coalesce((select auth.uid()),new.updated_by),
      new.attestation_note is not null
    );
  elsif new.status is distinct from old.status or new.attestation_note is distinct from old.attestation_note then
    insert into public.encounter_documentation_event(
      encounter_id,requirement_key,from_status,to_status,actor_user_id,note_present
    ) values(
      new.encounter_id,new.requirement_key,old.status,new.status,coalesce((select auth.uid()),new.updated_by),
      new.attestation_note is not null
    );
  end if;
  return new;
end;
$$;
revoke all on function public.audit_encounter_documentation_change() from public,anon,authenticated;

drop trigger if exists trg_audit_encounter_documentation_change on public.encounter_documentation_status;
create trigger trg_audit_encounter_documentation_change
after insert or update on public.encounter_documentation_status
for each row execute function public.audit_encounter_documentation_change();

create or replace function public.set_encounter_documentation_status(
  p_encounter_id uuid,
  p_requirement_key text,
  p_status text,
  p_attestation_note text default null
)
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
  if p_status not in ('missing','documented','not_applicable') then raise exception 'Invalid documentation status'; end if;
  if p_attestation_note is not null and length(p_attestation_note)>500 then raise exception 'Attestation note is too long'; end if;

  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then raise exception 'Encounter not found or not accessible'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_enc.practice_id and m.active and m.role='practitioner'
  ) then raise exception 'Practitioner role required for documentation attestation'; end if;

  if not exists(
    select 1 from public.encounter_documentation_requirement r
    where r.requirement_key=p_requirement_key and r.active
      and ('all'=any(r.applies_to) or v_enc.encounter_type=any(r.applies_to))
  ) then raise exception 'Documentation requirement does not apply to this encounter'; end if;

  insert into public.encounter_documentation_status(
    encounter_id,requirement_key,status,attestation_note,updated_by,updated_at
  ) values(
    p_encounter_id,p_requirement_key,p_status,nullif(trim(coalesce(p_attestation_note,'')),''),v_user,now()
  )
  on conflict(encounter_id,requirement_key) do update set
    status=excluded.status,
    attestation_note=excluded.attestation_note,
    updated_by=excluded.updated_by,
    updated_at=now();

  return p_encounter_id;
end;
$$;
revoke all on function public.set_encounter_documentation_status(uuid,text,text,text) from public,anon;
grant execute on function public.set_encounter_documentation_status(uuid,text,text,text) to authenticated;

create or replace function public.assess_encounter_readiness(p_encounter_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
declare
  v_enc public.practice_encounter%rowtype;
  v_completion_missing text[] := '{}';
  v_coding_missing text[] := '{}';
  v_billing_missing text[] := '{}';
  v_mit boolean := false;
  v_ccsa boolean := false;
  v_confirmed integer := 0;
  v_primary integer := 0;
  v_invoices integer := 0;
begin
  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then return jsonb_build_object('found',false,'ready',false,'reasons',jsonb_build_array('Encounter not found or not accessible')); end if;

  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=v_enc.practice_id and m.active
  ) then return jsonb_build_object('found',false,'ready',false,'reasons',jsonb_build_array('Active practice membership required')); end if;

  select coalesce(array_agg(r.display_name order by r.display_name) filter(where r.required_for_completion and coalesce(s.status,'missing')<>'documented'),'{}'::text[]),
         coalesce(array_agg(r.display_name order by r.display_name) filter(where r.required_for_coding and coalesce(s.status,'missing')<>'documented'),'{}'::text[]),
         coalesce(array_agg(r.display_name order by r.display_name) filter(where r.required_for_billing and coalesce(s.status,'missing')<>'documented'),'{}'::text[])
  into v_completion_missing,v_coding_missing,v_billing_missing
  from public.encounter_documentation_requirement r
  left join public.encounter_documentation_status s
    on s.encounter_id=v_enc.id and s.requirement_key=r.requirement_key
  where r.active and ('all'=any(r.applies_to) or v_enc.encounter_type=any(r.applies_to));

  select exists(
    select 1 from public.coding_source_release
    where authority='NDOH' and source_name='ICD-10 Master Industry Table' and status='active'
  ) into v_mit;

  select exists(
    select 1 from public.billing_code_reference b
    join public.source_dataset_release sr on sr.id=b.source_release_id
    join public.source_dataset d on d.id=sr.dataset_id
    where b.code_system='SAMA_CCSA' and b.active and sr.status='active' and d.licence_required
  ) into v_ccsa;

  select count(*) filter(where d.decision in ('ACCEPTED','MANUALLY_SELECTED')),
         count(*) filter(where d.decision in ('ACCEPTED','MANUALLY_SELECTED') and d.position='primary')
  into v_confirmed,v_primary
  from public.coding_decision d
  join public.coding_session s on s.id=d.coding_session_id
  join public.coding_source_release r on r.id=s.mit_release_id
  where s.encounter_id=v_enc.id and s.status='completed' and r.status='active';

  select count(*) into v_invoices
  from public.billing_invoice where encounter_id=v_enc.id;

  return jsonb_build_object(
    'found',true,
    'encounter_id',v_enc.id,
    'encounter_status',v_enc.status,
    'completion',jsonb_build_object(
      'ready',cardinality(v_completion_missing)=0,
      'missing',to_jsonb(v_completion_missing)
    ),
    'coding',jsonb_build_object(
      'documentation_ready',cardinality(v_coding_missing)=0,
      'missing_documentation',to_jsonb(v_coding_missing),
      'authoritative_mit_active',v_mit,
      'confirmed_codes',v_confirmed,
      'confirmed_primary_codes',v_primary,
      'coding_confirmed',v_confirmed>0 and v_primary>0,
      'ready_for_code10',cardinality(v_coding_missing)=0 and v_mit,
      'complete',cardinality(v_coding_missing)=0 and v_mit and v_confirmed>0 and v_primary>0
    ),
    'billing',jsonb_build_object(
      'documentation_ready',cardinality(v_billing_missing)=0,
      'missing_documentation',to_jsonb(v_billing_missing),
      'encounter_completed',v_enc.status='completed',
      'coding_confirmed',v_confirmed>0 and v_primary>0,
      'licensed_ccsa_active',v_ccsa,
      'scheme_billing_ready',cardinality(v_billing_missing)=0 and v_enc.status='completed' and v_confirmed>0 and v_primary>0 and v_ccsa,
      'linked_invoices',v_invoices
    )
  );
end;
$$;
revoke all on function public.assess_encounter_readiness(uuid) from public,anon;
grant execute on function public.assess_encounter_readiness(uuid) to authenticated;

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
  v_missing integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_enc from public.practice_encounter where id=p_encounter_id for update;
  if not found then raise exception 'Encounter not found or not accessible'; end if;
  if v_enc.status<>'open' then raise exception 'Only open encounters can be completed'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_enc.practice_id and m.active and m.role='practitioner'
  ) then raise exception 'Practitioner role required to complete an encounter'; end if;

  select count(*) into v_missing
  from public.encounter_documentation_requirement r
  left join public.encounter_documentation_status s
    on s.encounter_id=v_enc.id and s.requirement_key=r.requirement_key
  where r.active
    and r.required_for_completion
    and ('all'=any(r.applies_to) or v_enc.encounter_type=any(r.applies_to))
    and coalesce(s.status,'missing')<>'documented';

  if v_missing>0 then
    raise exception 'Required encounter documentation attestations are incomplete (% missing)',v_missing;
  end if;

  update public.practice_encounter
  set status='completed',completed_at=now(),updated_at=now()
  where id=p_encounter_id;

  return p_encounter_id;
end;
$$;

commit;
