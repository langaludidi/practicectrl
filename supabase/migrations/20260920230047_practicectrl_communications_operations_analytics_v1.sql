
begin;

create table if not exists public.communication_preference (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid not null references public.crm_patient(id) on delete cascade,
  channel text not null check (channel in ('email','sms','whatsapp','phone')),
  purpose text not null default 'administrative' check (purpose in ('administrative','appointment','billing','claims','clinical','marketing')),
  status text not null default 'unknown' check (status in ('unknown','allowed','restricted','withdrawn')),
  source text,
  recorded_by uuid references auth.users(id) on delete set null,
  recorded_at timestamptz not null default now(),
  unique(patient_id,channel,purpose)
);
create index if not exists communication_preference_practice_idx on public.communication_preference(practice_id,patient_id);
create index if not exists communication_preference_recorded_by_idx on public.communication_preference(recorded_by) where recorded_by is not null;

create table if not exists public.communication_thread (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  thread_type text not null default 'administrative' check (thread_type in ('administrative','appointment','billing','claim','referral','other')),
  subject text,
  status text not null default 'open' check (status in ('open','waiting_patient','waiting_practice','closed','suppressed')),
  owner_user_id uuid references auth.users(id) on delete set null,
  last_activity_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists communication_thread_queue_idx on public.communication_thread(practice_id,status,last_activity_at desc);
create index if not exists communication_thread_patient_idx on public.communication_thread(patient_id,last_activity_at desc) where patient_id is not null;
create index if not exists communication_thread_owner_idx on public.communication_thread(owner_user_id,status) where owner_user_id is not null;
create index if not exists communication_thread_created_by_idx on public.communication_thread(created_by) where created_by is not null;

create table if not exists public.communication_message (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.communication_thread(id) on delete cascade,
  direction text not null check (direction in ('inbound','outbound','internal')),
  channel text not null check (channel in ('email','sms','whatsapp','phone','internal')),
  status text not null default 'draft' check (status in ('draft','queued','sent','delivered','failed','received','cancelled')),
  recipient text,
  sender text,
  subject text,
  body text not null,
  contains_clinical_detail boolean not null default false,
  external_message_ref text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  constraint communication_message_body_ck check (length(trim(body)) > 0)
);
create index if not exists communication_message_thread_idx on public.communication_message(thread_id,created_at);
create index if not exists communication_message_created_by_idx on public.communication_message(created_by) where created_by is not null;

create table if not exists public.communication_template (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  template_key text not null,
  name text not null,
  channel text not null check (channel in ('email','sms','whatsapp')),
  purpose text not null check (purpose in ('appointment','billing','claim','referral','administrative')),
  subject_template text,
  body_template text not null,
  active boolean not null default true,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(practice_id,template_key)
);
create index if not exists communication_template_approved_by_idx on public.communication_template(approved_by) where approved_by is not null;

create table if not exists public.communication_delivery_event (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.communication_message(id) on delete cascade,
  event_type text not null check (event_type in ('queued','sent','delivered','bounced','failed','opened','replied','other')),
  provider text,
  provider_event_ref text,
  detail text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists communication_delivery_message_idx on public.communication_delivery_event(message_id,occurred_at);

create table if not exists public.operations_sla_policy (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  category text not null,
  priority text not null check (priority in ('low','normal','high','urgent')),
  target_minutes integer not null check (target_minutes > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(practice_id,category,priority)
);

create table if not exists public.operations_work_item (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  category text not null check (category in ('appointment_request','patient_follow_up','documentation','coding','billing','claim','revenue','communication','referral','compliance','other')),
  source_entity_type text,
  source_entity_id uuid,
  title text not null,
  description text,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'open' check (status in ('open','in_progress','waiting','blocked','completed','cancelled')),
  owner_user_id uuid references auth.users(id) on delete set null,
  due_at timestamptz,
  breached_at timestamptz,
  completed_at timestamptz,
  blocked_reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists operations_work_queue_idx on public.operations_work_item(practice_id,status,priority,due_at);
create index if not exists operations_work_owner_idx on public.operations_work_item(owner_user_id,status,due_at) where owner_user_id is not null;
create index if not exists operations_work_patient_idx on public.operations_work_item(patient_id,created_at desc) where patient_id is not null;
create index if not exists operations_work_created_by_idx on public.operations_work_item(created_by) where created_by is not null;

create table if not exists public.operations_work_event (
  id uuid primary key default gen_random_uuid(),
  work_item_id uuid not null references public.operations_work_item(id) on delete cascade,
  event_type text not null check (event_type in ('created','assigned','status_changed','priority_changed','comment','completed','reopened','other')),
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists operations_work_event_item_idx on public.operations_work_event(work_item_id,created_at);
create index if not exists operations_work_event_actor_idx on public.operations_work_event(actor_user_id) where actor_user_id is not null;

alter table public.communication_preference enable row level security;
alter table public.communication_thread enable row level security;
alter table public.communication_message enable row level security;
alter table public.communication_template enable row level security;
alter table public.communication_delivery_event enable row level security;
alter table public.operations_sla_policy enable row level security;
alter table public.operations_work_item enable row level security;
alter table public.operations_work_event enable row level security;

revoke all on table public.communication_preference from anon,authenticated;
revoke all on table public.communication_thread from anon,authenticated;
revoke all on table public.communication_message from anon,authenticated;
revoke all on table public.communication_template from anon,authenticated;
revoke all on table public.communication_delivery_event from anon,authenticated;
revoke all on table public.operations_sla_policy from anon,authenticated;
revoke all on table public.operations_work_item from anon,authenticated;
revoke all on table public.operations_work_event from anon,authenticated;

grant select,insert,update on table public.communication_preference to authenticated;
grant select,insert,update on table public.communication_thread to authenticated;
grant select,insert,update on table public.communication_message to authenticated;
grant select on table public.communication_template to authenticated;
grant select on table public.communication_delivery_event to authenticated;
grant select on table public.operations_sla_policy to authenticated;
grant select,insert,update on table public.operations_work_item to authenticated;
grant select,insert on table public.operations_work_event to authenticated;

create policy comm_pref_staff_read on public.communication_preference for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_preference.practice_id and m.active));
create policy comm_pref_staff_write on public.communication_preference for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_preference.practice_id and m.active and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_preference.practice_id and m.active and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')));

create policy comm_thread_staff_read on public.communication_thread for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_thread.practice_id and m.active));
create policy comm_thread_staff_write on public.communication_thread for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_thread.practice_id and m.active and m.role<>'auditor'))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_thread.practice_id and m.active and m.role<>'auditor'));

create policy comm_message_staff_read on public.communication_message for select to authenticated
using (exists (select 1 from public.communication_thread t join public.practice_staff_member m on m.practice_id=t.practice_id where t.id=communication_message.thread_id and m.user_id=(select auth.uid()) and m.active));
create policy comm_message_staff_write on public.communication_message for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.communication_thread t join public.practice_staff_member m on m.practice_id=t.practice_id where t.id=communication_message.thread_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor'))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.communication_thread t join public.practice_staff_member m on m.practice_id=t.practice_id where t.id=communication_message.thread_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor'));

create policy comm_template_staff_read on public.communication_template for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_template.practice_id and m.active));
create policy comm_delivery_staff_read on public.communication_delivery_event for select to authenticated
using (exists (select 1 from public.communication_message msg join public.communication_thread t on t.id=msg.thread_id join public.practice_staff_member m on m.practice_id=t.practice_id where msg.id=communication_delivery_event.message_id and m.user_id=(select auth.uid()) and m.active));

create policy operations_sla_staff_read on public.operations_sla_policy for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=operations_sla_policy.practice_id and m.active));
create policy operations_item_staff_read on public.operations_work_item for select to authenticated
using (exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=operations_work_item.practice_id and m.active));
create policy operations_item_staff_write on public.operations_work_item for all to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=operations_work_item.practice_id and m.active and m.role<>'auditor'))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=operations_work_item.practice_id and m.active and m.role<>'auditor'));
create policy operations_event_staff_read on public.operations_work_event for select to authenticated
using (exists (select 1 from public.operations_work_item w join public.practice_staff_member m on m.practice_id=w.practice_id where w.id=operations_work_event.work_item_id and m.user_id=(select auth.uid()) and m.active));
create policy operations_event_staff_insert on public.operations_work_event for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and (actor_user_id is null or actor_user_id=(select auth.uid())) and exists (select 1 from public.operations_work_item w join public.practice_staff_member m on m.practice_id=w.practice_id where w.id=operations_work_event.work_item_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor'));

create or replace function public.get_practicectrl_dashboard_metrics(p_practice_id uuid)
returns jsonb language sql stable security invoker set search_path=public,pg_temp
as $$
select jsonb_build_object(
  'patients', (select count(*) from public.crm_patient p where p.practice_id=p_practice_id and p.status='active'),
  'appointment_requests_open', (select count(*) from public.appointment_request r where r.practice_id=p_practice_id and r.status not in ('Closed','Duplicate','Confirmed in PMS')),
  'tasks_open', (select count(*) from public.crm_task t where t.practice_id=p_practice_id and t.status in ('open','in_progress','waiting')),
  'operations_open', (select count(*) from public.operations_work_item w where w.practice_id=p_practice_id and w.status in ('open','in_progress','waiting','blocked')),
  'communications_open', (select count(*) from public.communication_thread t where t.practice_id=p_practice_id and t.status<>'closed'),
  'invoices_outstanding', (select count(*) from public.billing_invoice i where i.practice_id=p_practice_id and i.status in ('final','part_paid','outstanding')),
  'invoice_balance', coalesce((select sum(i.balance_amount) from public.billing_invoice i where i.practice_id=p_practice_id and i.status in ('final','part_paid','outstanding')),0),
  'claims_exception', (select count(*) from public.claim_record c where c.practice_id=p_practice_id and c.claim_status in ('rejected','exception','partially_accepted')),
  'revenue_cases_actionable', (select count(*) from public.revenue_collection_case c where c.practice_id=p_practice_id and c.case_status in ('review_required','ready_for_contact','contacted','arrangement','waiting_scheme')),
  'revenue_cases_suppressed', (select count(*) from public.revenue_collection_case c where c.practice_id=p_practice_id and c.suppress_automation=true and c.case_status<>'resolved')
);
$$;
revoke all on function public.get_practicectrl_dashboard_metrics(uuid) from public,anon;
grant execute on function public.get_practicectrl_dashboard_metrics(uuid) to authenticated;

create or replace function public.get_revenue_ageing_summary(p_practice_id uuid)
returns jsonb language sql stable security invoker set search_path=public,pg_temp
as $$
with latest as (
  select max(snapshot_at) as snapshot_at from public.revenue_account_snapshot where practice_id=p_practice_id
)
select jsonb_build_object(
  'snapshot_at', latest.snapshot_at,
  'current', coalesce(sum(r.current_amount),0),
  'days_30', coalesce(sum(r.days_30),0),
  'days_60', coalesce(sum(r.days_60),0),
  'days_90', coalesce(sum(r.days_90),0),
  'days_120_plus', coalesce(sum(r.days_120_plus),0),
  'total', coalesce(sum(r.total_amount),0),
  'unresolved_liability', count(*) filter (where r.liability_status='unresolved'),
  'suppressed_accounts', count(*) filter (where r.collection_suppressed=true)
)
from latest
left join public.revenue_account_snapshot r on r.practice_id=p_practice_id and r.snapshot_at=latest.snapshot_at
group by latest.snapshot_at;
$$;
revoke all on function public.get_revenue_ageing_summary(uuid) from public,anon;
grant execute on function public.get_revenue_ageing_summary(uuid) to authenticated;

update public.platform_module set status='development'
where module_key in ('crm','billing','claims_revenue','communications','operations','analytics');
update public.practice_module pm set enabled=true,enabled_at=coalesce(enabled_at,now())
from public.platform_module m
where pm.module_id=m.id and m.module_key in ('crm','billing','claims_revenue','communications','operations','analytics');

insert into public.operations_sla_policy(practice_id,category,priority,target_minutes)
select p.id,x.category,x.priority,x.target_minutes
from public.practice p
cross join (values
  ('appointment_request','urgent',60),
  ('appointment_request','high',240),
  ('appointment_request','normal',1440),
  ('patient_follow_up','high',480),
  ('patient_follow_up','normal',2880),
  ('claim','high',1440),
  ('revenue','high',1440),
  ('documentation','high',480)
) x(category,priority,target_minutes)
where p.name='Dr Tembisa Tini Inc'
on conflict(practice_id,category,priority) do nothing;

commit;
