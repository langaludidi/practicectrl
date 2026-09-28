
begin;

create table if not exists public.integration_contact (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete cascade,
  contact_type text not null
    check (contact_type in ('sales','technical','coding','support','general','partner','other')),
  name text,
  email text,
  phone text,
  source_url text not null,
  verified_at timestamptz not null default now(),
  notes text,
  active boolean not null default true,
  constraint integration_contact_has_channel_ck check (
    email is not null or phone is not null
  )
);

create unique index if not exists integration_contact_provider_email_uq
  on public.integration_contact(provider_id, lower(email))
  where email is not null;
create index if not exists integration_contact_provider_idx
  on public.integration_contact(provider_id,contact_type,active);

alter table public.integration_contact enable row level security;
revoke all on table public.integration_contact from anon, authenticated;
grant select on table public.integration_contact to authenticated;

create policy integration_contact_staff_read
on public.integration_contact for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

insert into public.integration_contact(provider_id,contact_type,name,email,phone,source_url,notes)
select id,'general','MediKredit Enquiries','enquiries@medikredit.co.za','+27 11 770 6000',
       'https://www.medikredit.co.za/clients/practice-management-software-vendors/new-registration-practice-management-software-vendor/',
       'Verified general MediKredit contact. New PMS vendor page directs applicants to the Switch Integration Team; direct switch-team email is not stored here because the public search result redacts it.'
from public.integration_provider where slug='medikredit'
on conflict do nothing;

insert into public.integration_contact(provider_id,contact_type,name,email,phone,source_url,notes)
select id,'sales','Altron HealthTech Sales','healthtech.sales@altron.com','010 449 1000',
       'https://healthtech.altron.com/faq',
       'Published sales contact for SwitchOn/HealthTech enquiries.'
from public.integration_provider where slug='altron-switchon'
on conflict do nothing;

insert into public.integration_contact(provider_id,contact_type,name,email,phone,source_url,notes)
select id,'coding','SAMA Medical Coding Division','coding@samedical.org','012 481 2048',
       'https://coding.samedical.org/downloads/emdcm/Application%20Files/SAMA%20eDBM_3_0_0_114/data/MDCMHome.html',
       'Published Medical Coding Division contact for eMDCM/eCCSA coding matters.'
from public.integration_provider where slug='sama'
on conflict do nothing;

commit;
