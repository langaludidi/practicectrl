
create table public.patient_intake_consent_document(
 id uuid primary key default gen_random_uuid(),
 practice_id uuid references public.practice(id) on delete cascade,
 consent_key text not null,
 version text not null,
 title text not null,
 body text not null,
 required boolean not null default true,
 active boolean not null default true,
 effective_from date not null default current_date,
 effective_to date,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(practice_id,consent_key,version)
);
alter table public.patient_intake_consent_document enable row level security;
create policy intake_consent_document_staff_read on public.patient_intake_consent_document for select to authenticated using(practice_id is null or exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_consent_document.practice_id and m.active));
grant select on public.patient_intake_consent_document to authenticated;
insert into public.patient_intake_consent_document(practice_id,consent_key,version,title,body,required,active)
values
(null,'accuracy','v1','Accuracy declaration','I confirm that the information I have supplied is accurate to the best of my knowledge.',true,true),
(null,'privacy_notice','v1','Privacy acknowledgement','I acknowledge that the practice will process my personal and health information for healthcare, administration, billing and related lawful purposes, and that the practice privacy notice will be made available to me.',true,true),
(null,'account_responsibility','v1','Account responsibility','I understand that medical-scheme payment is not guaranteed and that I remain responsible for amounts lawfully due under the practice terms.',true,true);

