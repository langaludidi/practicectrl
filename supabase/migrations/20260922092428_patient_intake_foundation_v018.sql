
create table public.patient_intake_session(
 id uuid primary key default gen_random_uuid(),
 practice_id uuid not null references public.practice(id) on delete cascade,
 appointment_id uuid references public.practice_appointment(id) on delete set null,
 existing_patient_id uuid references public.crm_patient(id) on delete set null,
 source text not null default 'online' check(source in('online','tablet','paper','staff_capture')),
 status text not null default 'invited' check(status in('invited','opened','in_progress','submitted','validation_required','under_review','verified','applied','expired','cancelled')),
 token_hash text,
 token_expires_at timestamptz,
 patient_display_name text,
 patient_phone_hint text,
 patient_email_hint text,
 draft_json jsonb not null default '{}'::jsonb,
 submitted_json jsonb,
 form_version integer not null default 1,
 opened_at timestamptz,
 submitted_at timestamptz,
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 applied_patient_id uuid references public.crm_patient(id) on delete set null,
 applied_at timestamptz,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(token_hash)
);
create table public.patient_intake_event(
 id uuid primary key default gen_random_uuid(),
 intake_session_id uuid not null references public.patient_intake_session(id) on delete cascade,
 event_type text not null,
 actor_type text not null check(actor_type in('patient','staff','system')),
 actor_user_id uuid references auth.users(id) on delete set null,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create table public.patient_intake_consent_acceptance(
 id uuid primary key default gen_random_uuid(),
 intake_session_id uuid not null references public.patient_intake_session(id) on delete cascade,
 consent_key text not null,
 document_version text not null,
 status text not null check(status in('accepted','declined')),
 accepted_at timestamptz,
 signature_method text check(signature_method is null or signature_method in('typed_name','drawn','wet_signature','checkbox')),
 signer_name text,
 evidence_json jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 unique(intake_session_id,consent_key,document_version)
);
create table public.patient_intake_match_candidate(
 id uuid primary key default gen_random_uuid(),
 intake_session_id uuid not null references public.patient_intake_session(id) on delete cascade,
 practice_id uuid not null references public.practice(id) on delete cascade,
 patient_id uuid not null references public.crm_patient(id) on delete cascade,
 match_score numeric(5,2) not null check(match_score between 0 and 100),
 match_reasons text[] not null default '{}',
 status text not null default 'pending' check(status in('pending','confirmed_match','not_match','dismissed')),
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 unique(intake_session_id,patient_id)
);
create table public.patient_address(
 id uuid primary key default gen_random_uuid(),
 practice_id uuid not null references public.practice(id) on delete cascade,
 patient_id uuid not null references public.crm_patient(id) on delete cascade,
 address_type text not null check(address_type in('physical','postal')),
 line1 text, line2 text, suburb text, city text, province text, postal_code text, country_code text not null default 'ZA',
 active boolean not null default true,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.patient_emergency_contact(
 id uuid primary key default gen_random_uuid(),
 practice_id uuid not null references public.practice(id) on delete cascade,
 patient_id uuid not null references public.crm_patient(id) on delete cascade,
 full_name text not null,
 relationship text,
 phone text not null,
 email text,
 active boolean not null default true,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.patient_communication_preference(
 patient_id uuid primary key references public.crm_patient(id) on delete cascade,
 practice_id uuid not null references public.practice(id) on delete cascade,
 preferred_channel text check(preferred_channel is null or preferred_channel in('whatsapp','sms','email','phone')),
 appointment_reminders boolean not null default true,
 account_notifications boolean not null default true,
 clinical_notifications boolean not null default true,
 results_notifications boolean not null default true,
 marketing_messages boolean not null default false,
 updated_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now()
);
create index patient_intake_session_practice_status_idx on public.patient_intake_session(practice_id,status,created_at desc);
create index patient_intake_session_appointment_idx on public.patient_intake_session(appointment_id) where appointment_id is not null;
create index patient_intake_event_session_idx on public.patient_intake_event(intake_session_id,created_at);
create index patient_intake_match_practice_idx on public.patient_intake_match_candidate(practice_id,status,match_score desc);
create index patient_address_patient_idx on public.patient_address(patient_id,active);
create index patient_emergency_contact_patient_idx on public.patient_emergency_contact(patient_id,active);

create trigger intake_appointment_tenant_guard before insert or update of practice_id,appointment_id on public.patient_intake_session for each row execute function public.enforce_same_practice_reference('practice_appointment','appointment_id');
create trigger intake_existing_patient_tenant_guard before insert or update of practice_id,existing_patient_id on public.patient_intake_session for each row execute function public.enforce_same_practice_reference('crm_patient','existing_patient_id');
create trigger intake_applied_patient_tenant_guard before insert or update of practice_id,applied_patient_id on public.patient_intake_session for each row execute function public.enforce_same_practice_reference('crm_patient','applied_patient_id');
create trigger intake_match_patient_tenant_guard before insert or update of practice_id,patient_id on public.patient_intake_match_candidate for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger patient_address_tenant_guard before insert or update of practice_id,patient_id on public.patient_address for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger patient_emergency_contact_tenant_guard before insert or update of practice_id,patient_id on public.patient_emergency_contact for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');
create trigger patient_communication_tenant_guard before insert or update of practice_id,patient_id on public.patient_communication_preference for each row execute function public.enforce_same_practice_reference('crm_patient','patient_id');

alter table public.patient_intake_session enable row level security;
alter table public.patient_intake_event enable row level security;
alter table public.patient_intake_consent_acceptance enable row level security;
alter table public.patient_intake_match_candidate enable row level security;
alter table public.patient_address enable row level security;
alter table public.patient_emergency_contact enable row level security;
alter table public.patient_communication_preference enable row level security;

create policy intake_staff_read on public.patient_intake_session for select to authenticated using(exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_session.practice_id and m.active));
create policy intake_staff_manage on public.patient_intake_session for all to authenticated using(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_session.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin'))) with check(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_session.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));
create policy intake_event_staff_read on public.patient_intake_event for select to authenticated using(exists(select 1 from public.patient_intake_session s join public.practice_staff_member m on m.practice_id=s.practice_id where s.id=patient_intake_event.intake_session_id and m.user_id=(select auth.uid()) and m.active));
create policy intake_consent_staff_read on public.patient_intake_consent_acceptance for select to authenticated using(exists(select 1 from public.patient_intake_session s join public.practice_staff_member m on m.practice_id=s.practice_id where s.id=patient_intake_consent_acceptance.intake_session_id and m.user_id=(select auth.uid()) and m.active));
create policy intake_match_staff_read on public.patient_intake_match_candidate for select to authenticated using(exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_match_candidate.practice_id and m.active));
create policy intake_match_staff_update on public.patient_intake_match_candidate for update to authenticated using(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_match_candidate.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin'))) with check(true);
create policy patient_address_staff on public.patient_address for all to authenticated using(exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_address.practice_id and m.active)) with check(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_address.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));
create policy patient_emergency_contact_staff on public.patient_emergency_contact for all to authenticated using(exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_emergency_contact.practice_id and m.active)) with check(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_emergency_contact.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));
create policy patient_communication_staff on public.patient_communication_preference for all to authenticated using(exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_communication_preference.practice_id and m.active)) with check(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_communication_preference.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));

grant select,insert,update on public.patient_intake_session to authenticated;
grant select on public.patient_intake_event,public.patient_intake_consent_acceptance to authenticated;
grant select,update on public.patient_intake_match_candidate to authenticated;
grant select,insert,update,delete on public.patient_address,public.patient_emergency_contact,public.patient_communication_preference to authenticated;

insert into public.platform_module(module_key,display_name,descriptor,flagship,enabled_by_default,ai_enabled,voice_enabled,status)
values('patient_intake','Patient Intake & Registration','Secure online, tablet and paper-backed patient registration, consent, verification and appointment-linked intake',false,true,true,true,'development')
on conflict(module_key) do update set display_name=excluded.display_name,descriptor=excluded.descriptor,enabled_by_default=true,ai_enabled=true,voice_enabled=true,status='development';

