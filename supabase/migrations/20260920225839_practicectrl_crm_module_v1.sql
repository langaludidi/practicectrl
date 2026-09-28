
begin;

create table if not exists public.crm_patient (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  source_system text not null default 'PracticeCtrl',
  source_patient_ref text,
  account_ref text,
  file_ref text,
  first_name text,
  last_name text,
  display_name text not null,
  date_of_birth date,
  coding_sex public.coding_gender_rule,
  primary_phone text,
  primary_email text,
  status text not null default 'active' check (status in ('active','inactive','deceased','merged')),
  data_quality_status text not null default 'unverified' check (data_quality_status in ('unverified','source_verified','staff_verified','needs_review')),
  source_last_seen_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_patient_display_name_ck check (length(trim(display_name)) > 0)
);
create unique index if not exists crm_patient_source_ref_uq on public.crm_patient(practice_id,source_system,source_patient_ref) where source_patient_ref is not null;
create index if not exists crm_patient_practice_name_idx on public.crm_patient(practice_id,last_name,first_name,display_name);
create index if not exists crm_patient_account_idx on public.crm_patient(practice_id,account_ref) where account_ref is not null;
create index if not exists crm_patient_file_idx on public.crm_patient(practice_id,file_ref) where file_ref is not null;
create index if not exists crm_patient_created_by_idx on public.crm_patient(created_by) where created_by is not null;
create index if not exists crm_patient_updated_by_idx on public.crm_patient(updated_by) where updated_by is not null;

create table if not exists public.crm_patient_external_link (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.crm_patient(id) on delete cascade,
  source_system text not null,
  source_entity text not null default 'patient',
  external_ref text not null,
  source_row_hash text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(source_system,source_entity,external_ref)
);
create index if not exists crm_patient_external_link_patient_idx on public.crm_patient_external_link(patient_id);

create table if not exists public.crm_contact_point (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.crm_patient(id) on delete cascade,
  contact_type text not null check (contact_type in ('mobile','phone','email','whatsapp','other')),
  value text not null,
  label text,
  is_primary boolean not null default false,
  consent_status text not null default 'unknown' check (consent_status in ('unknown','allowed','restricted','withdrawn')),
  source_system text,
  source_last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_contact_value_ck check (length(trim(value)) > 0)
);
create index if not exists crm_contact_patient_idx on public.crm_contact_point(patient_id,contact_type,is_primary desc);

create table if not exists public.crm_referral_source (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  source_type text not null check (source_type in ('practitioner','facility','patient','digital','employer','scheme','other')),
  name text not null,
  organisation text,
  contact_email text,
  contact_phone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists crm_referral_source_practice_idx on public.crm_referral_source(practice_id,active,name);

create table if not exists public.crm_patient_referral (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid not null references public.crm_patient(id) on delete cascade,
  referral_source_id uuid references public.crm_referral_source(id) on delete restrict,
  referral_date date,
  referral_reference text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists crm_patient_referral_patient_idx on public.crm_patient_referral(patient_id,referral_date desc);
create index if not exists crm_patient_referral_source_idx on public.crm_patient_referral(referral_source_id) where referral_source_id is not null;
create index if not exists crm_patient_referral_created_by_idx on public.crm_patient_referral(created_by) where created_by is not null;

create table if not exists public.appointment_request (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  source text not null default 'internal' check (source in ('website','phone','email','whatsapp','walk_in','internal','import','other')),
  external_ref text,
  requester_name text not null,
  requester_phone text,
  requester_email text,
  requested_service text,
  preferred_date date,
  preferred_time text,
  message text,
  status text not null default 'New' check (status in ('New','Contacted','Confirmed in PMS','Alternative Offered','Unable to Reach','Closed','Duplicate')),
  assigned_to uuid references auth.users(id) on delete set null,
  pms_reference text,
  contacted_at timestamptz,
  confirmed_at timestamptz,
  closed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint appointment_request_name_ck check (length(trim(requester_name)) > 0)
);
create unique index if not exists appointment_request_external_ref_uq on public.appointment_request(practice_id,source,external_ref) where external_ref is not null;
create index if not exists appointment_request_queue_idx on public.appointment_request(practice_id,status,created_at desc);
create index if not exists appointment_request_assigned_idx on public.appointment_request(assigned_to,status) where assigned_to is not null;
create index if not exists appointment_request_patient_idx on public.appointment_request(patient_id,created_at desc) where patient_id is not null;
create index if not exists appointment_request_created_by_idx on public.appointment_request(created_by) where created_by is not null;

create table if not exists public.crm_task (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  appointment_request_id uuid references public.appointment_request(id) on delete set null,
  category text not null default 'follow_up' check (category in ('follow_up','recall','referral','appointment','documentation','billing','claim','communication','other')),
  title text not null,
  description text,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'open' check (status in ('open','in_progress','waiting','completed','cancelled')),
  owner_user_id uuid references auth.users(id) on delete set null,
  due_at timestamptz,
  completed_at timestamptz,
  completion_note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_task_title_ck check (length(trim(title)) > 0)
);
create index if not exists crm_task_queue_idx on public.crm_task(practice_id,status,due_at,priority);
create index if not exists crm_task_owner_idx on public.crm_task(owner_user_id,status,due_at) where owner_user_id is not null;
create index if not exists crm_task_patient_idx on public.crm_task(patient_id,created_at desc) where patient_id is not null;
create index if not exists crm_task_request_idx on public.crm_task(appointment_request_id) where appointment_request_id is not null;
create index if not exists crm_task_created_by_idx on public.crm_task(created_by) where created_by is not null;

create table if not exists public.crm_timeline_event (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid not null references public.crm_patient(id) on delete cascade,
  event_type text not null check (event_type in ('patient_created','patient_updated','appointment_request','task','communication','coding','invoice','claim','payment','referral','note','other')),
  event_at timestamptz not null default now(),
  title text not null,
  summary text,
  entity_type text,
  entity_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  source_system text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists crm_timeline_patient_idx on public.crm_timeline_event(patient_id,event_at desc);
create index if not exists crm_timeline_actor_idx on public.crm_timeline_event(actor_user_id,event_at desc) where actor_user_id is not null;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='billing_invoice_patient_id_fkey') then
    alter table public.billing_invoice add constraint billing_invoice_patient_id_fkey foreign key(patient_id) references public.crm_patient(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname='claim_record_patient_id_fkey') then
    alter table public.claim_record add constraint claim_record_patient_id_fkey foreign key(patient_id) references public.crm_patient(id) on delete restrict;
  end if;
end $$;

alter table public.crm_patient enable row level security;
alter table public.crm_patient_external_link enable row level security;
alter table public.crm_contact_point enable row level security;
alter table public.crm_referral_source enable row level security;
alter table public.crm_patient_referral enable row level security;
alter table public.appointment_request enable row level security;
alter table public.crm_task enable row level security;
alter table public.crm_timeline_event enable row level security;

revoke all on table public.crm_patient from anon,authenticated;
revoke all on table public.crm_patient_external_link from anon,authenticated;
revoke all on table public.crm_contact_point from anon,authenticated;
revoke all on table public.crm_referral_source from anon,authenticated;
revoke all on table public.crm_patient_referral from anon,authenticated;
revoke all on table public.appointment_request from anon,authenticated;
revoke all on table public.crm_task from anon,authenticated;
revoke all on table public.crm_timeline_event from anon,authenticated;

grant select,insert,update on table public.crm_patient to authenticated;
grant select on table public.crm_patient_external_link to authenticated;
grant select,insert,update,delete on table public.crm_contact_point to authenticated;
grant select,insert,update on table public.crm_referral_source to authenticated;
grant select,insert on table public.crm_patient_referral to authenticated;
grant select,insert,update on table public.appointment_request to authenticated;
grant select,insert,update on table public.crm_task to authenticated;
grant select,insert on table public.crm_timeline_event to authenticated;

create policy crm_patient_staff_read on public.crm_patient for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_patient.practice_id and m.active));
create policy crm_patient_staff_insert on public.crm_patient for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid()) and exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_patient.practice_id and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
));
create policy crm_patient_staff_update on public.crm_patient for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_patient.practice_id and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
))
with check (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_patient.practice_id and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
));

create policy crm_external_link_staff_read on public.crm_patient_external_link for select to authenticated
using (exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_patient_external_link.patient_id and m.user_id=(select auth.uid()) and m.active
));

create policy crm_contact_staff_read on public.crm_contact_point for select to authenticated
using (exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_contact_point.patient_id and m.user_id=(select auth.uid()) and m.active
));
create policy crm_contact_staff_write on public.crm_contact_point for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_contact_point.patient_id and m.user_id=(select auth.uid()) and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
))
with check (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_contact_point.patient_id and m.user_id=(select auth.uid()) and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
));

create policy crm_referral_staff_read on public.crm_referral_source for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_referral_source.practice_id and m.active));
create policy crm_referral_staff_write on public.crm_referral_source for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_referral_source.practice_id and m.active and m.role in ('reception','practice_manager','clinical_admin','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_referral_source.practice_id and m.active and m.role in ('reception','practice_manager','clinical_admin','system_admin')));

create policy crm_patient_referral_staff_read on public.crm_patient_referral for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_referral.practice_id and m.active));
create policy crm_patient_referral_staff_insert on public.crm_patient_referral for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid()) and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_patient_referral.practice_id and m.active and m.role<>'auditor'));

create policy appointment_request_staff_read on public.appointment_request for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=appointment_request.practice_id and m.active));
create policy appointment_request_staff_insert on public.appointment_request for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and (created_by is null or created_by=(select auth.uid())) and exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=appointment_request.practice_id and m.active
    and m.role in ('reception','practice_manager','clinical_admin','system_admin')
));
create policy appointment_request_staff_update on public.appointment_request for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=appointment_request.practice_id and m.active
    and m.role in ('reception','practice_manager','clinical_admin','system_admin')
))
with check (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=appointment_request.practice_id and m.active
    and m.role in ('reception','practice_manager','clinical_admin','system_admin')
));

create policy crm_task_staff_read on public.crm_task for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_task.practice_id and m.active));
create policy crm_task_staff_insert on public.crm_task for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid()) and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_task.practice_id and m.active and m.role<>'auditor'));
create policy crm_task_staff_update on public.crm_task for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_task.practice_id and m.active and m.role<>'auditor'))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_task.practice_id and m.active and m.role<>'auditor'));

create policy crm_timeline_staff_read on public.crm_timeline_event for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_timeline_event.practice_id and m.active));
create policy crm_timeline_staff_insert on public.crm_timeline_event for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and (actor_user_id is null or actor_user_id=(select auth.uid())) and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_timeline_event.practice_id and m.active and m.role<>'auditor'));

commit;
