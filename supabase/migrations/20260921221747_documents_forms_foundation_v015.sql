create table public.document_template (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid references public.practice(id) on delete cascade,
  template_key text not null,
  name text not null,
  category text not null check (category in ('consent','clinical_letter','medical_certificate','referral','clinical_report','administrative','billing','other')),
  clinical_data boolean not null default false,
  version integer not null default 1 check (version>0),
  status text not null default 'active' check (status in ('draft','active','retired')),
  schema_json jsonb not null default '{}'::jsonb,
  body_template text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique nulls not distinct (practice_id,template_key,version)
);
create index document_template_practice_idx on public.document_template(practice_id,name);

create table public.patient_document (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  patient_id uuid references public.crm_patient(id) on delete restrict,
  encounter_id uuid references public.practice_encounter(id) on delete restrict,
  template_id uuid references public.document_template(id) on delete restrict,
  document_type text not null,
  title text not null,
  clinical_data boolean not null default false,
  status text not null default 'draft' check (status in ('draft','generated','signed','void')),
  content_json jsonb not null default '{}'::jsonb,
  storage_bucket text,
  storage_path text,
  mime_type text,
  byte_size bigint,
  sha256 text,
  created_by uuid not null references auth.users(id) on delete restrict,
  generated_at timestamptz,
  signed_by uuid references auth.users(id) on delete restrict,
  signed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint patient_document_storage_ck check (
    (storage_bucket is null and storage_path is null and sha256 is null)
    or (storage_bucket is not null and storage_path is not null and sha256 is not null)
  )
);
create index patient_document_patient_idx on public.patient_document(practice_id,patient_id,created_at desc);
create index patient_document_encounter_idx on public.patient_document(encounter_id,created_at desc) where encounter_id is not null;
create index patient_document_template_idx on public.patient_document(template_id) where template_id is not null;
create index patient_document_created_by_idx on public.patient_document(created_by);

create table public.form_response (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  patient_id uuid not null references public.crm_patient(id) on delete restrict,
  encounter_id uuid references public.practice_encounter(id) on delete restrict,
  template_id uuid not null references public.document_template(id) on delete restrict,
  clinical_data boolean not null default false,
  status text not null default 'draft' check (status in ('draft','submitted','signed','void')),
  answers jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id) on delete restrict,
  submitted_by uuid references auth.users(id) on delete restrict,
  submitted_at timestamptz,
  signed_by uuid references auth.users(id) on delete restrict,
  signed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index form_response_patient_idx on public.form_response(practice_id,patient_id,created_at desc);
create index form_response_template_idx on public.form_response(template_id,created_at desc);
create index form_response_encounter_idx on public.form_response(encounter_id) where encounter_id is not null;
create index form_response_created_by_idx on public.form_response(created_by);

create table public.patient_consent (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete restrict,
  patient_id uuid not null references public.crm_patient(id) on delete restrict,
  form_response_id uuid references public.form_response(id) on delete restrict,
  consent_type text not null,
  consent_scope text,
  status text not null default 'active' check (status in ('active','withdrawn','expired','superseded')),
  granted_at timestamptz not null default now(),
  effective_from date,
  effective_to date,
  withdrawn_at timestamptz,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint patient_consent_dates_ck check (effective_to is null or effective_from is null or effective_to>=effective_from),
  constraint patient_consent_withdrawn_ck check ((status='withdrawn' and withdrawn_at is not null) or status<>'withdrawn')
);
create index patient_consent_patient_idx on public.patient_consent(practice_id,patient_id,status,granted_at desc);
create index patient_consent_form_idx on public.patient_consent(form_response_id) where form_response_id is not null;
create index patient_consent_recorded_by_idx on public.patient_consent(recorded_by);

create table public.patient_document_event (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.patient_document(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index patient_document_event_document_idx on public.patient_document_event(document_id,created_at desc);
create index patient_document_event_actor_idx on public.patient_document_event(actor_user_id) where actor_user_id is not null;

alter table public.document_template enable row level security;
alter table public.patient_document enable row level security;
alter table public.form_response enable row level security;
alter table public.patient_consent enable row level security;
alter table public.patient_document_event enable row level security;

revoke all on public.document_template,public.patient_document,public.form_response,public.patient_consent,public.patient_document_event from anon,authenticated;
grant select,insert,update on public.document_template to authenticated;
grant select,insert,update on public.patient_document to authenticated;
grant select,insert,update on public.form_response to authenticated;
grant select,insert,update on public.patient_consent to authenticated;
grant select,insert on public.patient_document_event to authenticated;

create policy document_template_read on public.document_template for select to authenticated using (
  practice_id is null
  or exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=document_template.practice_id and m.active)
);
create policy document_template_insert on public.document_template for insert to authenticated with check (
  practice_id is not null and ((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=document_template.practice_id and m.active and m.role in ('practice_manager','system_admin'))
);
create policy document_template_update on public.document_template for update to authenticated using (
  practice_id is not null and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=document_template.practice_id and m.active and m.role in ('practice_manager','system_admin'))
) with check (
  practice_id is not null and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=document_template.practice_id and m.active and m.role in ('practice_manager','system_admin'))
);

create policy patient_document_read on public.patient_document for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_document.practice_id and m.active
    and (not patient_document.clinical_data or m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')))
);
create policy patient_document_insert on public.patient_document for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_document.practice_id and m.active and m.role<>'auditor'
    and (not patient_document.clinical_data or m.role in ('practitioner','clinical_admin')))
);
create policy patient_document_update on public.patient_document for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2' and status in ('draft','generated') and
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_document.practice_id and m.active and m.role<>'auditor'
    and (not patient_document.clinical_data or m.role in ('practitioner','clinical_admin')))
) with check (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_document.practice_id and m.active and m.role<>'auditor'
    and (not patient_document.clinical_data or m.role in ('practitioner','clinical_admin')))
);

create policy form_response_read on public.form_response for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=form_response.practice_id and m.active
    and (not form_response.clinical_data or m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')))
);
create policy form_response_insert on public.form_response for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=form_response.practice_id and m.active and m.role<>'auditor'
    and (not form_response.clinical_data or m.role in ('practitioner','clinical_admin')))
);
create policy form_response_update on public.form_response for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2' and status='draft'
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=form_response.practice_id and m.active and m.role<>'auditor'
    and (not form_response.clinical_data or m.role in ('practitioner','clinical_admin')))
) with check (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=form_response.practice_id and m.active and m.role<>'auditor'
    and (not form_response.clinical_data or m.role in ('practitioner','clinical_admin')))
);

create policy patient_consent_read on public.patient_consent for select to authenticated using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_consent.practice_id and m.active)
);
create policy patient_consent_insert on public.patient_consent for insert to authenticated with check (
  ((select auth.jwt())->>'aal')='aal2' and recorded_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_consent.practice_id and m.active and m.role<>'auditor')
);
create policy patient_consent_update on public.patient_consent for update to authenticated using (
  ((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_consent.practice_id and m.active and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin'))
) with check (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_consent.practice_id and m.active and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin'))
);

create policy patient_document_event_read on public.patient_document_event for select to authenticated using (
  exists(select 1 from public.patient_document d join public.practice_staff_member m on m.practice_id=d.practice_id where d.id=patient_document_event.document_id and m.user_id=(select auth.uid()) and m.active
    and (not d.clinical_data or m.role in ('practitioner','clinical_admin','practice_manager','system_admin','auditor')))
);
create policy patient_document_event_insert on public.patient_document_event for insert to authenticated with check (
  actor_user_id=(select auth.uid()) and exists(select 1 from public.patient_document d join public.practice_staff_member m on m.practice_id=d.practice_id where d.id=patient_document_event.document_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor')
);

insert into public.document_template(practice_id,template_key,name,category,clinical_data,version,status,schema_json,body_template)
values
  (null,'popia_consent','POPIA and information-processing consent','consent',false,1,'active','{"fields":["consent","communication_preferences"]}'::jsonb,'Patient information-processing and communication consent'),
  (null,'procedure_consent','Procedure consent','consent',true,1,'active','{"fields":["procedure","risks","alternatives","consent"]}'::jsonb,'Procedure-specific informed consent'),
  (null,'referral_letter','Referral letter','referral',true,1,'active','{"fields":["recipient","reason","clinical_summary"]}'::jsonb,'Clinical referral letter'),
  (null,'medical_certificate','Medical certificate','medical_certificate',true,1,'active','{"fields":["date_from","date_to","restrictions"]}'::jsonb,'Medical certificate'),
  (null,'clinical_report','Clinical report','clinical_report',true,1,'active','{"fields":["purpose","history","findings","opinion"]}'::jsonb,'Structured clinical report')
on conflict(practice_id,template_key,version) do nothing;

insert into public.platform_module(module_key,display_name,descriptor,flagship,enabled_by_default,ai_enabled,voice_enabled,status)
values('documents_forms','Forms & Documents','Patient forms, consent records, clinical letters and governed document generation',false,true,true,true,'development')
on conflict(module_key) do update set display_name=excluded.display_name,descriptor=excluded.descriptor,enabled_by_default=true,ai_enabled=true,voice_enabled=true,status='development';

insert into public.practice_module(practice_id,module_id,enabled,enabled_at,configuration)
select p.id,m.id,true,now(),'{}'::jsonb from public.practice p join public.platform_module m on m.module_key='documents_forms'
on conflict(practice_id,module_id) do update set enabled=true,enabled_at=coalesce(public.practice_module.enabled_at,excluded.enabled_at);

create trigger tenant_guard_patient_document_patient before insert or update of practice_id,patient_id on public.patient_document for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger tenant_guard_patient_document_encounter before insert or update of practice_id,encounter_id on public.patient_document for each row when (new.encounter_id is not null) execute function public.enforce_same_practice_reference('practice_encounter','encounter_id');
create trigger tenant_guard_form_response_patient before insert or update of practice_id,patient_id on public.form_response for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger tenant_guard_form_response_encounter before insert or update of practice_id,encounter_id on public.form_response for each row when (new.encounter_id is not null) execute function public.enforce_same_practice_reference('practice_encounter','encounter_id');
create trigger tenant_guard_patient_consent_patient before insert or update of practice_id,patient_id on public.patient_consent for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
