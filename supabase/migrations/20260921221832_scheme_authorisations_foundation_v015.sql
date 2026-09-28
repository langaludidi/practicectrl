create table public.scheme_authorisation (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  patient_id uuid not null references public.crm_patient(id) on delete restrict,
  membership_id uuid not null references public.crm_patient_scheme_membership(id) on delete restrict,
  encounter_id uuid references public.practice_encounter(id) on delete restrict,
  medical_scheme_id uuid references public.medical_scheme(id) on delete restrict,
  medical_scheme_option_id uuid references public.medical_scheme_option(id) on delete restrict,
  request_reference text,
  authorisation_number text,
  status text not null default 'draft' check (status in ('draft','requested','pending','approved','partially_approved','declined','expired','cancelled')),
  request_date date,
  decision_date date,
  effective_from date,
  effective_to date,
  requested_amount numeric check (requested_amount is null or requested_amount>=0),
  approved_amount numeric check (approved_amount is null or approved_amount>=0),
  requested_units numeric check (requested_units is null or requested_units>=0),
  approved_units numeric check (approved_units is null or approved_units>=0),
  conditions text,
  decline_reason text,
  notes text,
  source_system text not null default 'PracticeCtrl',
  external_reference text,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheme_authorisation_dates_ck check (effective_to is null or effective_from is null or effective_to>=effective_from),
  constraint scheme_authorisation_approval_ck check (
    status not in ('approved','partially_approved') or nullif(trim(coalesce(authorisation_number,'')),'') is not null
  )
);
create index scheme_authorisation_patient_idx on public.scheme_authorisation(practice_id,patient_id,created_at desc);
create index scheme_authorisation_membership_idx on public.scheme_authorisation(membership_id,created_at desc);
create index scheme_authorisation_encounter_idx on public.scheme_authorisation(encounter_id) where encounter_id is not null;
create index scheme_authorisation_scheme_idx on public.scheme_authorisation(medical_scheme_id,status);
create index scheme_authorisation_created_by_idx on public.scheme_authorisation(created_by);

create table public.scheme_authorisation_item (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  authorisation_id uuid not null references public.scheme_authorisation(id) on delete cascade,
  line_no integer not null,
  code_system text not null,
  code text not null,
  description_snapshot text not null,
  diagnosis_codes text[] not null default '{}',
  requested_units numeric,
  approved_units numeric,
  requested_amount numeric,
  approved_amount numeric,
  status text not null default 'requested' check (status in ('requested','approved','partially_approved','declined')),
  conditions text,
  created_at timestamptz not null default now(),
  unique(authorisation_id,line_no)
);
create index scheme_authorisation_item_practice_idx on public.scheme_authorisation_item(practice_id,authorisation_id);

create table public.scheme_authorisation_event (
  id uuid primary key default gen_random_uuid(),
  authorisation_id uuid not null references public.scheme_authorisation(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index scheme_authorisation_event_auth_idx on public.scheme_authorisation_event(authorisation_id,created_at desc);
create index scheme_authorisation_event_actor_idx on public.scheme_authorisation_event(actor_user_id) where actor_user_id is not null;

alter table public.billing_invoice add column scheme_authorisation_id uuid references public.scheme_authorisation(id) on delete restrict;
alter table public.claim_record add column scheme_authorisation_id uuid references public.scheme_authorisation(id) on delete restrict;
create index billing_invoice_authorisation_idx on public.billing_invoice(scheme_authorisation_id) where scheme_authorisation_id is not null;
create index claim_record_authorisation_idx on public.claim_record(scheme_authorisation_id) where scheme_authorisation_id is not null;

alter table public.scheme_authorisation enable row level security;
alter table public.scheme_authorisation_item enable row level security;
alter table public.scheme_authorisation_event enable row level security;

revoke all on public.scheme_authorisation,public.scheme_authorisation_item,public.scheme_authorisation_event from anon,authenticated;
grant select,insert,update on public.scheme_authorisation to authenticated;
grant select,insert,update on public.scheme_authorisation_item to authenticated;
grant select,insert on public.scheme_authorisation_event to authenticated;

create policy scheme_authorisation_read on public.scheme_authorisation for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation.practice_id and m.active
    and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin','auditor'))
);
create policy scheme_authorisation_insert on public.scheme_authorisation for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation.practice_id and m.active
    and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin'))
);
create policy scheme_authorisation_update on public.scheme_authorisation for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation.practice_id and m.active
    and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin'))
) with check (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation.practice_id and m.active
    and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin'))
);

create policy scheme_authorisation_item_read on public.scheme_authorisation_item for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation_item.practice_id and m.active)
);
create policy scheme_authorisation_item_insert on public.scheme_authorisation_item for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation_item.practice_id and m.active
    and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin'))
);
create policy scheme_authorisation_item_update on public.scheme_authorisation_item for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation_item.practice_id and m.active
    and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin'))
) with check (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=scheme_authorisation_item.practice_id and m.active)
);

create policy scheme_authorisation_event_read on public.scheme_authorisation_event for select to authenticated using (
  exists(select 1 from public.scheme_authorisation a join public.practice_staff_member m on m.practice_id=a.practice_id where a.id=scheme_authorisation_event.authorisation_id and m.user_id=(select auth.uid()) and m.active)
);
create policy scheme_authorisation_event_insert on public.scheme_authorisation_event for insert to authenticated with check (
  actor_user_id=(select auth.uid()) and exists(select 1 from public.scheme_authorisation a join public.practice_staff_member m on m.practice_id=a.practice_id where a.id=scheme_authorisation_event.authorisation_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor')
);

create or replace function public.create_scheme_authorisation(
  p_practice_id uuid,
  p_patient_id uuid,
  p_membership_id uuid,
  p_encounter_id uuid,
  p_request_reference text,
  p_request_date date,
  p_requested_amount numeric,
  p_requested_units numeric,
  p_notes text
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_membership public.crm_patient_scheme_membership%rowtype;
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')) then raise exception 'Authorisation-management role required'; end if;
  select * into v_membership from public.crm_patient_scheme_membership where id=p_membership_id and practice_id=p_practice_id and patient_id=p_patient_id;
  if not found then raise exception 'Patient scheme membership not found in the selected practice'; end if;
  if p_encounter_id is not null and not exists(select 1 from public.practice_encounter e where e.id=p_encounter_id and e.practice_id=p_practice_id and e.patient_id=p_patient_id) then raise exception 'Encounter does not belong to this patient/practice'; end if;
  insert into public.scheme_authorisation(practice_id,patient_id,membership_id,encounter_id,medical_scheme_id,medical_scheme_option_id,request_reference,status,request_date,requested_amount,requested_units,notes,created_by,updated_by)
  values(p_practice_id,p_patient_id,p_membership_id,p_encounter_id,v_membership.medical_scheme_id,v_membership.medical_scheme_option_id,nullif(trim(coalesce(p_request_reference,'')),''),'requested',coalesce(p_request_date,current_date),p_requested_amount,p_requested_units,nullif(trim(coalesce(p_notes,'')),''),v_user,v_user)
  returning id into v_id;
  insert into public.scheme_authorisation_event(authorisation_id,event_type,actor_user_id,metadata) values(v_id,'requested',v_user,jsonb_build_object('request_reference',p_request_reference));
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,source_system,source_reference)
  values(p_practice_id,p_patient_id,'scheme_authorisation_requested',now(),'Medical scheme authorisation requested',coalesce(p_request_reference,'Authorisation request'),'PracticeCtrl',v_id::text);
  return v_id;
end;
$$;

create or replace function public.update_scheme_authorisation_status(
  p_authorisation_id uuid,
  p_status text,
  p_authorisation_number text,
  p_decision_date date,
  p_effective_from date,
  p_effective_to date,
  p_approved_amount numeric,
  p_approved_units numeric,
  p_conditions text,
  p_decline_reason text
) returns uuid
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_auth public.scheme_authorisation%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_status not in ('requested','pending','approved','partially_approved','declined','expired','cancelled') then raise exception 'Invalid authorisation status'; end if;
  select * into v_auth from public.scheme_authorisation where id=p_authorisation_id for update;
  if not found then raise exception 'Authorisation not found or not accessible'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_auth.practice_id and m.active and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')) then raise exception 'Authorisation-management role required'; end if;
  if p_status in ('approved','partially_approved') and length(trim(coalesce(p_authorisation_number,v_auth.authorisation_number,'')))<1 then raise exception 'Authorisation number is required for an approval'; end if;
  if p_effective_to is not null and p_effective_from is not null and p_effective_to<p_effective_from then raise exception 'Effective-to date cannot precede effective-from date'; end if;
  update public.scheme_authorisation set
    status=p_status,
    authorisation_number=coalesce(nullif(trim(coalesce(p_authorisation_number,'')),''),authorisation_number),
    decision_date=coalesce(p_decision_date,decision_date),
    effective_from=coalesce(p_effective_from,effective_from),
    effective_to=coalesce(p_effective_to,effective_to),
    approved_amount=coalesce(p_approved_amount,approved_amount),
    approved_units=coalesce(p_approved_units,approved_units),
    conditions=coalesce(nullif(trim(coalesce(p_conditions,'')),''),conditions),
    decline_reason=case when p_status='declined' then coalesce(nullif(trim(coalesce(p_decline_reason,'')),''),decline_reason) else decline_reason end,
    updated_by=v_user,updated_at=now()
  where id=p_authorisation_id;
  insert into public.scheme_authorisation_event(authorisation_id,event_type,actor_user_id,metadata)
  values(p_authorisation_id,'status_changed',v_user,jsonb_build_object('from_status',v_auth.status,'to_status',p_status,'authorisation_number',p_authorisation_number));
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,source_system,source_reference)
  values(v_auth.practice_id,v_auth.patient_id,'scheme_authorisation_status',now(),'Medical scheme authorisation '||replace(p_status,'_',' '),coalesce(p_authorisation_number,v_auth.request_reference,'Authorisation'),'PracticeCtrl',p_authorisation_id::text);
  return p_authorisation_id;
end;
$$;

revoke all on function public.create_scheme_authorisation(uuid,uuid,uuid,uuid,text,date,numeric,numeric,text) from public,anon;
revoke all on function public.update_scheme_authorisation_status(uuid,text,text,date,date,date,numeric,numeric,text,text) from public,anon;
grant execute on function public.create_scheme_authorisation(uuid,uuid,uuid,uuid,text,date,numeric,numeric,text) to authenticated;
grant execute on function public.update_scheme_authorisation_status(uuid,text,text,date,date,date,numeric,numeric,text,text) to authenticated;

insert into public.platform_module(module_key,display_name,descriptor,flagship,enabled_by_default,ai_enabled,voice_enabled,status)
values('authorisations','Medical Scheme Authorisations','Pre-authorisation requests, approvals, conditions and service/claim linkage',false,true,true,false,'development')
on conflict(module_key) do update set display_name=excluded.display_name,descriptor=excluded.descriptor,enabled_by_default=true,ai_enabled=true,voice_enabled=false,status='development';
insert into public.practice_module(practice_id,module_id,enabled,enabled_at,configuration)
select p.id,m.id,true,now(),'{}'::jsonb from public.practice p join public.platform_module m on m.module_key='authorisations'
on conflict(practice_id,module_id) do update set enabled=true,enabled_at=coalesce(public.practice_module.enabled_at,excluded.enabled_at);

create trigger tenant_guard_scheme_authorisation_patient before insert or update of practice_id,patient_id on public.scheme_authorisation for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger tenant_guard_scheme_authorisation_membership before insert or update of practice_id,membership_id on public.scheme_authorisation for each row execute function public.enforce_same_practice_reference('crm_patient_scheme_membership','membership_id');
create trigger tenant_guard_scheme_authorisation_encounter before insert or update of practice_id,encounter_id on public.scheme_authorisation for each row when (new.encounter_id is not null) execute function public.enforce_same_practice_reference('practice_encounter','encounter_id');
create trigger tenant_guard_scheme_authorisation_item before insert or update of practice_id,authorisation_id on public.scheme_authorisation_item for each row execute function public.enforce_same_practice_reference('scheme_authorisation','authorisation_id');

create or replace function public.guard_invoice_claim_authorisation_tenant() returns trigger
language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_practice uuid;
begin
  if new.scheme_authorisation_id is null then return new; end if;
  select practice_id into v_practice from public.scheme_authorisation where id=new.scheme_authorisation_id;
  if v_practice is distinct from new.practice_id then raise exception 'Cross-practice authorisation reference blocked' using errcode='23514'; end if;
  return new;
end; $$;
create trigger tenant_guard_billing_invoice_authorisation before insert or update of practice_id,scheme_authorisation_id on public.billing_invoice for each row execute function public.guard_invoice_claim_authorisation_tenant();
create trigger tenant_guard_claim_record_authorisation before insert or update of practice_id,scheme_authorisation_id on public.claim_record for each row execute function public.guard_invoice_claim_authorisation_tenant();
