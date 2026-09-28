
begin;

create table if not exists public.communication_delivery_provider (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null unique,
  display_name text not null,
  channel text not null check (channel in ('email','sms','whatsapp')),
  status text not null default 'research' check (status in ('research','sandbox','approved','production','retired')),
  transport_ready boolean not null default false,
  health_data_approved boolean not null default false,
  credential_secret_ref text,
  data_processing_reference text,
  region_summary text,
  retention_summary text,
  notes text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists communication_delivery_provider_reviewed_by_idx
  on public.communication_delivery_provider(reviewed_by) where reviewed_by is not null;

create table if not exists public.practice_communication_route (
  practice_id uuid not null references public.practice(id) on delete cascade,
  channel text not null check (channel in ('email','sms','whatsapp')),
  environment text not null check (environment in ('staging','production')),
  provider_id uuid not null references public.communication_delivery_provider(id) on delete restrict,
  enabled boolean not null default false,
  configuration jsonb not null default '{}'::jsonb,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(practice_id,channel,environment)
);
create index if not exists practice_communication_route_provider_idx
  on public.practice_communication_route(provider_id);
create index if not exists practice_communication_route_approved_by_idx
  on public.practice_communication_route(approved_by) where approved_by is not null;

create table if not exists public.communication_dispatch_request (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.communication_message(id) on delete restrict,
  provider_id uuid not null references public.communication_delivery_provider(id) on delete restrict,
  environment text not null check (environment in ('staging','production')),
  status text not null default 'queued' check (status in ('queued','sending','sent','failed','cancelled')),
  idempotency_key text not null,
  queued_by uuid references auth.users(id) on delete set null,
  queued_at timestamptz not null default now(),
  completed_at timestamptz,
  error_code text,
  error_summary text,
  unique(message_id,environment,idempotency_key)
);
create index if not exists communication_dispatch_message_idx
  on public.communication_dispatch_request(message_id,queued_at desc);
create index if not exists communication_dispatch_provider_idx
  on public.communication_dispatch_request(provider_id,status);
create index if not exists communication_dispatch_queued_by_idx
  on public.communication_dispatch_request(queued_by) where queued_by is not null;

alter table public.communication_delivery_provider enable row level security;
alter table public.practice_communication_route enable row level security;
alter table public.communication_dispatch_request enable row level security;

revoke all on table public.communication_delivery_provider from anon,authenticated;
revoke all on table public.practice_communication_route from anon,authenticated;
revoke all on table public.communication_dispatch_request from anon,authenticated;

grant select(
  id,provider_key,display_name,channel,status,transport_ready,health_data_approved,
  data_processing_reference,region_summary,retention_summary,notes,reviewed_at,created_at,updated_at
) on public.communication_delivery_provider to authenticated;
grant select on table public.practice_communication_route to authenticated;
grant select on table public.communication_dispatch_request to authenticated;

create policy communication_provider_staff_read
on public.communication_delivery_provider for select to authenticated
using (exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active));

create policy communication_route_staff_read
on public.practice_communication_route for select to authenticated
using (exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice_communication_route.practice_id and m.active));

create policy communication_dispatch_staff_read
on public.communication_dispatch_request for select to authenticated
using (exists(
  select 1
  from public.communication_message msg
  join public.communication_thread t on t.id=msg.thread_id
  join public.practice_staff_member m on m.practice_id=t.practice_id
  where msg.id=communication_dispatch_request.message_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('practice_manager','system_admin','auditor')
));

create or replace function public.assess_communication_send_readiness(
  p_message_id uuid,
  p_environment text default 'staging'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
declare
  v_msg public.communication_message%rowtype;
  v_thread public.communication_thread%rowtype;
  v_route public.practice_communication_route%rowtype;
  v_provider public.communication_delivery_provider%rowtype;
  v_purpose text;
  v_pref text;
  v_reasons jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
begin
  if p_environment not in ('staging','production') then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Invalid communication environment'),'warnings','[]'::jsonb);
  end if;

  select * into v_msg from public.communication_message where id=p_message_id;
  if not found then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Message not found or not accessible'),'warnings','[]'::jsonb);
  end if;
  select * into v_thread from public.communication_thread where id=v_msg.thread_id;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=v_thread.practice_id and m.active
  ) then
    return jsonb_build_object('ready',false,'reasons',jsonb_build_array('Active practice membership required'),'warnings','[]'::jsonb);
  end if;

  if v_msg.direction<>'outbound' then v_reasons:=v_reasons||jsonb_build_array('Only outbound messages can be dispatched'); end if;
  if v_msg.status not in ('draft','failed') then v_reasons:=v_reasons||jsonb_build_array('Message must be draft or failed before queuing'); end if;
  if v_msg.channel not in ('email','sms','whatsapp') then v_reasons:=v_reasons||jsonb_build_array('This channel is not supported by the outbound dispatcher'); end if;
  if length(trim(coalesce(v_msg.recipient,'')))<2 then v_reasons:=v_reasons||jsonb_build_array('Recipient address or number is missing'); end if;

  v_purpose := case v_thread.thread_type
    when 'appointment' then 'appointment'
    when 'billing' then 'billing'
    when 'claim' then 'claims'
    else 'administrative' end;

  if v_thread.patient_id is not null then
    select status into v_pref
    from public.communication_preference
    where patient_id=v_thread.patient_id and channel=v_msg.channel and purpose=v_purpose
    limit 1;

    if v_pref in ('restricted','withdrawn') then
      v_reasons:=v_reasons||jsonb_build_array('Patient communication preference blocks this channel/purpose');
    elsif v_pref is null or v_pref='unknown' then
      v_warnings:=v_warnings||jsonb_build_array('No explicit patient channel preference is recorded; confirm the lawful communication basis');
    end if;
  end if;

  select * into v_route
  from public.practice_communication_route
  where practice_id=v_thread.practice_id and channel=v_msg.channel and environment=p_environment and enabled;

  if not found then
    v_reasons:=v_reasons||jsonb_build_array('No enabled communication-provider route exists for this channel/environment');
  else
    select * into v_provider from public.communication_delivery_provider where id=v_route.provider_id;
    if v_provider.status not in ('approved','production') or not v_provider.transport_ready then
      v_reasons:=v_reasons||jsonb_build_array('Configured communication provider is not approved and transport-ready');
    end if;
    if v_msg.contains_clinical_detail and not v_provider.health_data_approved then
      v_reasons:=v_reasons||jsonb_build_array('Configured provider is not approved for communication containing health information');
    end if;
  end if;

  return jsonb_build_object(
    'ready',jsonb_array_length(v_reasons)=0,
    'reasons',v_reasons,
    'warnings',v_warnings,
    'message_id',p_message_id,
    'channel',v_msg.channel,
    'environment',p_environment,
    'provider_id',case when v_route.provider_id is null then null else v_route.provider_id end
  );
end;
$$;
revoke all on function public.assess_communication_send_readiness(uuid,text) from public,anon;
grant execute on function public.assess_communication_send_readiness(uuid,text) to authenticated;

create or replace function public.queue_communication_message(
  p_message_id uuid,
  p_environment text default 'staging'
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_ready jsonb;
  v_msg public.communication_message%rowtype;
  v_thread public.communication_thread%rowtype;
  v_route public.practice_communication_route%rowtype;
  v_id uuid;
  v_key text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_msg from public.communication_message where id=p_message_id for update;
  if not found then raise exception 'Message not found or not accessible'; end if;
  select * into v_thread from public.communication_thread where id=v_msg.thread_id;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_thread.practice_id and m.active and m.role<>'auditor'
  ) then raise exception 'Active staff role required'; end if;

  v_ready:=public.assess_communication_send_readiness(p_message_id,p_environment);
  if coalesce((v_ready->>'ready')::boolean,false)=false then
    raise exception 'Message is not dispatch-ready: %',coalesce(v_ready->'reasons','[]'::jsonb)::text;
  end if;

  select * into v_route from public.practice_communication_route
  where practice_id=v_thread.practice_id and channel=v_msg.channel and environment=p_environment and enabled;

  v_key := encode(extensions.digest(p_message_id::text||':'||p_environment||':'||coalesce(v_msg.recipient,'')||':'||v_msg.body,'sha256'),'hex');

  insert into public.communication_dispatch_request(
    message_id,provider_id,environment,status,idempotency_key,queued_by
  ) values(
    p_message_id,v_route.provider_id,p_environment,'queued',v_key,v_user
  ) returning id into v_id;

  update public.communication_message set status='queued' where id=p_message_id;
  insert into public.communication_delivery_event(message_id,event_type,provider,detail)
  select p_message_id,'queued',p.display_name,'Queued through governed PracticeCtrl dispatch route'
  from public.communication_delivery_provider p where p.id=v_route.provider_id;

  return v_id;
end;
$$;
revoke all on function public.queue_communication_message(uuid,text) from public,anon;
grant execute on function public.queue_communication_message(uuid,text) to authenticated;

commit;
