
begin;

create table if not exists public.integration_outreach_event (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.integration_provider(id) on delete cascade,
  channel text not null check (channel in ('email','phone','meeting','portal','other')),
  direction text not null check (direction in ('outbound','inbound')),
  subject text,
  external_thread_ref text,
  external_message_ref text,
  sent_at timestamptz,
  received_at timestamptz,
  summary text,
  created_at timestamptz not null default now()
);

create index if not exists integration_outreach_provider_time_idx
  on public.integration_outreach_event(provider_id, coalesce(sent_at,received_at,created_at) desc);

alter table public.integration_outreach_event enable row level security;
revoke all on table public.integration_outreach_event from anon, authenticated;
grant select on table public.integration_outreach_event to authenticated;

drop policy if exists integration_outreach_staff_read on public.integration_outreach_event;
create policy integration_outreach_staff_read
on public.integration_outreach_event for select to authenticated
using (exists (
  select 1 from public.practice_staff_member m
  where m.user_id=(select auth.uid()) and m.active
));

insert into public.integration_outreach_event
(provider_id,channel,direction,subject,external_thread_ref,external_message_ref,sent_at,summary)
select id,'email','outbound',
       'PracticeCtrl — PMS Vendor Integration, HealthNet ST Accreditation and NAPPI Data Enquiry',
       '1a0c095efe1a5c25','1a0c0a57ea88b238',now(),
       'Requested PMS vendor onboarding, HealthNet ST XML/XSD specification, transaction coverage, sandbox/UAT, accreditation, pricing, POPIA/data-processing requirements and NAPPI licensing.'
from public.integration_provider where slug='medikredit';

insert into public.integration_outreach_event
(provider_id,channel,direction,subject,external_thread_ref,external_message_ref,sent_at,summary)
select id,'email','outbound',
       'PracticeCtrl — SwitchOn Third-Party PMS Integration Enquiry',
       '1a0c095f8f9f061a','1a0c0a5856b2b102',now(),
       'Requested third-party PMS integration path, technical protocol/specification, sandbox/UAT, vendor certification, pricing, consent/eRA and POPIA/data-processing requirements.'
from public.integration_provider where slug='altron-switchon';

insert into public.integration_outreach_event
(provider_id,channel,direction,subject,external_thread_ref,external_message_ref,sent_at,summary)
select id,'email','outbound',
       'PracticeCtrl — CCSA/eMDCM Software Platform Licensing and Structured Data Enquiry',
       '1a0c095ff94b86c9','1a0c0a58a5348209',now(),
       'Requested software-platform licensing route, structured data/API/feed availability, permitted server-side use, updates/versioning, commercial pricing and attribution requirements.'
from public.integration_provider where slug='sama';

update public.integration_requirement r
set status='waiting_external'
from public.integration_provider p
where r.provider_id=p.id
  and p.slug='medikredit'
  and r.status='open';

update public.integration_requirement r
set status='waiting_external'
from public.integration_provider p
where r.provider_id=p.id
  and p.slug='altron-switchon'
  and r.status='open';

update public.integration_requirement r
set status='waiting_external'
from public.integration_provider p
where r.provider_id=p.id
  and p.slug='sama'
  and r.status='open';

update public.integration_provider
set lifecycle_status='contracting', updated_at=now()
where slug in ('medikredit','altron-switchon','sama');

commit;

