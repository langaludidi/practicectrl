-- Recovered schema-only communications automation foundation from the connected project.
-- The recorded v0.29 migration only asserted these objects existed.
-- No patient, contact, message, or tenant data is copied.
begin;
create extension if not exists pg_cron with schema pg_catalog;

create table public."communication_automation_rule" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "rule_key" text not null,
  "name" text not null,
  "trigger_type" text not null,
  "purpose" text not null,
  "channel_strategy" text default 'preferred'::text not null,
  "template_group_key" text not null,
  "lead_minutes" integer default 1440 not null,
  "environment" text default 'staging'::text not null,
  "enabled" boolean default false not null,
  "requires_explicit_preference" boolean default true not null,
  "quiet_start" time without time zone default '20:00:00'::time without time zone not null,
  "quiet_end" time without time zone default '08:00:00'::time without time zone not null,
  "created_by" uuid,
  "approved_by" uuid,
  "approved_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."communication_automation_job" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "rule_id" uuid not null,
  "patient_id" uuid not null,
  "source_entity_type" text not null,
  "source_entity_id" uuid not null,
  "channel" text,
  "scheduled_for" timestamp with time zone not null,
  "status" text default 'scheduled'::text not null,
  "message_id" uuid,
  "suppression_reason" text,
  "block_reason" text,
  "dedupe_key" text not null,
  "last_attempt_at" timestamp with time zone,
  "attempt_count" integer default 0 not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table public."communication_automation_event" (
  "id" uuid default gen_random_uuid() not null,
  "practice_id" uuid not null,
  "job_id" uuid not null,
  "event_type" text not null,
  "detail" text,
  "metadata" jsonb default '{}'::jsonb not null,
  "actor_user_id" uuid,
  "occurred_at" timestamp with time zone default now() not null
);

alter table public."communication_automation_rule" add constraint "communication_automation_rule_channel_strategy_check" CHECK ((channel_strategy = ANY (ARRAY['preferred'::text, 'email'::text, 'sms'::text, 'whatsapp'::text])));
alter table public."communication_automation_rule" add constraint "communication_automation_rule_check" CHECK (((enabled = false) OR ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))));
alter table public."communication_automation_rule" add constraint "communication_automation_rule_environment_check" CHECK ((environment = ANY (ARRAY['staging'::text, 'production'::text])));
alter table public."communication_automation_rule" add constraint "communication_automation_rule_lead_minutes_check" CHECK (((lead_minutes >= 0) AND (lead_minutes <= 43200)));
alter table public."communication_automation_rule" add constraint "communication_automation_rule_pkey" PRIMARY KEY (id);
alter table public."communication_automation_rule" add constraint "communication_automation_rule_practice_id_rule_key_environm_key" UNIQUE (practice_id, rule_key, environment);
alter table public."communication_automation_rule" add constraint "communication_automation_rule_purpose_check" CHECK ((purpose = ANY (ARRAY['appointment'::text, 'billing'::text, 'claims'::text, 'administrative'::text])));
alter table public."communication_automation_rule" add constraint "communication_automation_rule_trigger_type_check" CHECK ((trigger_type = ANY (ARRAY['appointment_reminder'::text, 'appointment_confirmation'::text, 'intake_followup'::text, 'account_notification'::text, 'claim_status'::text, 'authorisation_status'::text])));
alter table public."communication_automation_job" add constraint "communication_automation_job_attempt_count_check" CHECK ((attempt_count >= 0));
alter table public."communication_automation_job" add constraint "communication_automation_job_channel_check" CHECK ((channel = ANY (ARRAY['email'::text, 'sms'::text, 'whatsapp'::text])));
alter table public."communication_automation_job" add constraint "communication_automation_job_dedupe_key_key" UNIQUE (dedupe_key);
alter table public."communication_automation_job" add constraint "communication_automation_job_pkey" PRIMARY KEY (id);
alter table public."communication_automation_job" add constraint "communication_automation_job_source_entity_type_check" CHECK ((source_entity_type = ANY (ARRAY['appointment'::text, 'intake'::text, 'invoice'::text, 'claim'::text, 'authorisation'::text])));
alter table public."communication_automation_job" add constraint "communication_automation_job_status_check" CHECK ((status = ANY (ARRAY['scheduled'::text, 'materialized'::text, 'queued'::text, 'suppressed'::text, 'blocked'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])));
alter table public."communication_automation_event" add constraint "communication_automation_event_event_type_check" CHECK ((event_type = ANY (ARRAY['scheduled'::text, 'suppressed'::text, 'blocked'::text, 'materialized'::text, 'queued'::text, 'completed'::text, 'failed'::text, 'cancelled'::text, 'retried'::text])));
alter table public."communication_automation_event" add constraint "communication_automation_event_pkey" PRIMARY KEY (id);

alter table public."communication_automation_rule" add constraint "communication_automation_rule_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."communication_automation_rule" add constraint "communication_automation_rule_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."communication_automation_rule" add constraint "communication_automation_rule_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."communication_automation_job" add constraint "communication_automation_job_message_id_fkey" FOREIGN KEY (message_id) REFERENCES communication_message(id) ON DELETE SET NULL;
alter table public."communication_automation_job" add constraint "communication_automation_job_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES crm_patient(id) ON DELETE CASCADE;
alter table public."communication_automation_job" add constraint "communication_automation_job_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;
alter table public."communication_automation_job" add constraint "communication_automation_job_rule_id_fkey" FOREIGN KEY (rule_id) REFERENCES communication_automation_rule(id) ON DELETE CASCADE;
alter table public."communication_automation_event" add constraint "communication_automation_event_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public."communication_automation_event" add constraint "communication_automation_event_job_id_fkey" FOREIGN KEY (job_id) REFERENCES communication_automation_job(id) ON DELETE CASCADE;
alter table public."communication_automation_event" add constraint "communication_automation_event_practice_id_fkey" FOREIGN KEY (practice_id) REFERENCES practice(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS communication_automation_rule_practice_idx ON public.communication_automation_rule USING btree (practice_id, enabled, trigger_type);
CREATE INDEX IF NOT EXISTS communication_automation_rule_created_by_idx ON public.communication_automation_rule USING btree (created_by) WHERE (created_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS communication_automation_rule_approved_by_idx ON public.communication_automation_rule USING btree (approved_by) WHERE (approved_by IS NOT NULL);
CREATE INDEX IF NOT EXISTS communication_automation_job_due_idx ON public.communication_automation_job USING btree (practice_id, status, scheduled_for);
CREATE INDEX IF NOT EXISTS communication_automation_job_source_idx ON public.communication_automation_job USING btree (source_entity_type, source_entity_id);
CREATE INDEX IF NOT EXISTS communication_automation_job_patient_idx ON public.communication_automation_job USING btree (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS communication_automation_job_rule_idx ON public.communication_automation_job USING btree (rule_id);
CREATE INDEX IF NOT EXISTS communication_automation_job_message_idx ON public.communication_automation_job USING btree (message_id) WHERE (message_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS communication_automation_event_job_idx ON public.communication_automation_event USING btree (job_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS communication_automation_event_practice_idx ON public.communication_automation_event USING btree (practice_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS communication_automation_event_actor_idx ON public.communication_automation_event USING btree (actor_user_id) WHERE (actor_user_id IS NOT NULL);

alter table public."communication_automation_rule" enable row level security;
revoke all on public."communication_automation_rule" from anon, authenticated;
grant select, insert, update on public."communication_automation_rule" to authenticated;
create policy "communication_automation_rule_manage" on public."communication_automation_rule" for insert to authenticated with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = communication_automation_rule.practice_id) AND m.active AND (m.role = ANY (ARRAY['practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role]))))) AND ((created_by IS NULL) OR (created_by = ( SELECT auth.uid() AS uid))) AND ((approved_by IS NULL) OR (approved_by = ( SELECT auth.uid() AS uid)))));
create policy "communication_automation_rule_read" on public."communication_automation_rule" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = communication_automation_rule.practice_id) AND m.active))));
create policy "communication_automation_rule_update" on public."communication_automation_rule" for update to authenticated using ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = communication_automation_rule.practice_id) AND m.active AND (m.role = ANY (ARRAY['practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role]))))))) with check ((((( SELECT auth.jwt() AS jwt) ->> 'aal'::text) = 'aal2'::text) AND (EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = communication_automation_rule.practice_id) AND m.active AND (m.role = ANY (ARRAY['practice_manager'::practice_staff_role, 'system_admin'::practice_staff_role]))))) AND ((approved_by IS NULL) OR (approved_by = ( SELECT auth.uid() AS uid)))));
alter table public."communication_automation_job" enable row level security;
revoke all on public."communication_automation_job" from anon, authenticated;
grant select on public."communication_automation_job" to authenticated;
create policy "communication_automation_job_read" on public."communication_automation_job" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = communication_automation_job.practice_id) AND m.active))));
alter table public."communication_automation_event" enable row level security;
revoke all on public."communication_automation_event" from anon, authenticated;
grant select on public."communication_automation_event" to authenticated;
create policy "communication_automation_event_read" on public."communication_automation_event" for select to authenticated using ((EXISTS ( SELECT 1
   FROM practice_staff_member m
  WHERE ((m.user_id = ( SELECT auth.uid() AS uid)) AND (m.practice_id = communication_automation_event.practice_id) AND m.active))));

CREATE OR REPLACE FUNCTION private.process_communication_automation(p_practice_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  v_scheduled integer:=0;
  v_materialized integer:=0;
  v_queued integer:=0;
  v_suppressed integer:=0;
  v_blocked integer:=0;
  r record;
  v_channel text;
  v_recipient text;
  v_permission jsonb;
  v_template public.communication_template%rowtype;
  v_practice public.practice%rowtype;
  v_patient public.crm_patient%rowtype;
  v_appointment public.practice_appointment%rowtype;
  v_context jsonb;
  v_thread uuid;
  v_message uuid;
  v_route public.practice_communication_route%rowtype;
  v_provider public.communication_delivery_provider%rowtype;
  v_dispatch uuid;
  v_key text;
  v_local_now timestamp;
  v_next_local timestamp;
begin
  insert into public.communication_automation_job(
    practice_id,rule_id,patient_id,source_entity_type,source_entity_id,scheduled_for,status,dedupe_key
  )
  select a.practice_id,ar.id,a.patient_id,'appointment',a.id,
         a.starts_at - make_interval(mins=>ar.lead_minutes),
         'scheduled',
         encode(extensions.digest(ar.id::text||':appointment:'||a.id::text,'sha256'),'hex')
  from public.communication_automation_rule ar
  join public.practice_appointment a on a.practice_id=ar.practice_id
  where (p_practice_id is null or ar.practice_id=p_practice_id) and ar.enabled and ar.trigger_type='appointment_reminder'
    and a.status in ('booked','confirmed')
    and a.starts_at>now()
    and a.starts_at<=now()+interval '14 days'
  on conflict (dedupe_key) do nothing;
  get diagnostics v_scheduled=row_count;

  update public.communication_automation_job j
  set status='cancelled',updated_at=now(),block_reason=null,suppression_reason='Source appointment is no longer eligible.'
  where (p_practice_id is null or j.practice_id=p_practice_id) and j.status in ('scheduled','blocked') and j.source_entity_type='appointment'
    and exists(select 1 from public.practice_appointment a where a.id=j.source_entity_id and a.status not in ('booked','confirmed'));

  for r in
    select j.*, ar.purpose,ar.channel_strategy,ar.template_group_key,ar.environment,ar.requires_explicit_preference,
           ar.quiet_start,ar.quiet_end
    from public.communication_automation_job j
    join public.communication_automation_rule ar on ar.id=j.rule_id
    where (p_practice_id is null or j.practice_id=p_practice_id) and j.status in ('scheduled','blocked') and j.scheduled_for<=now() and ar.enabled
    order by j.scheduled_for
    limit 100
    for update of j skip locked
  loop
    update public.communication_automation_job
    set last_attempt_at=now(),attempt_count=attempt_count+1,updated_at=now()
    where id=r.id;

    select * into v_patient from public.crm_patient where id=r.patient_id and practice_id=r.practice_id;
    if not found then
      update public.communication_automation_job set status='failed',block_reason='Patient record unavailable',updated_at=now() where id=r.id;
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      values(r.practice_id,r.id,'failed','Patient record unavailable');
      continue;
    end if;

    select * into v_practice from public.practice where id=r.practice_id;
    v_local_now:=now() at time zone coalesce(v_practice.timezone,'Africa/Johannesburg');
    if (r.quiet_start>r.quiet_end and (v_local_now::time>=r.quiet_start or v_local_now::time<r.quiet_end))
       or (r.quiet_start<r.quiet_end and v_local_now::time>=r.quiet_start and v_local_now::time<r.quiet_end) then
      v_next_local:=((case when v_local_now::time>=r.quiet_start then v_local_now::date+1 else v_local_now::date end)::date + r.quiet_end);
      update public.communication_automation_job
      set scheduled_for=(v_next_local at time zone coalesce(v_practice.timezone,'Africa/Johannesburg')),updated_at=now()
      where id=r.id;
      continue;
    end if;

    if r.channel_strategy='preferred' then
      select preferred_channel into v_channel
      from public.patient_communication_preference
      where practice_id=r.practice_id and patient_id=r.patient_id;
      if v_channel is null or v_channel not in ('email','sms','whatsapp') then
        update public.communication_automation_job
        set status='suppressed',suppression_reason='No explicit supported preferred channel is recorded.',updated_at=now()
        where id=r.id;
        insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
        values(r.practice_id,r.id,'suppressed','No explicit supported preferred channel is recorded.');
        v_suppressed:=v_suppressed+1;
        continue;
      end if;
    else
      v_channel:=r.channel_strategy;
    end if;

    v_permission:=private.communication_permission_internal(r.practice_id,r.patient_id,v_channel,r.purpose,r.requires_explicit_preference);
    if coalesce((v_permission->>'allowed')::boolean,false)=false then
      update public.communication_automation_job
      set status='suppressed',channel=v_channel,suppression_reason=coalesce(v_permission->>'reason','Communication preference prevents automation.'),updated_at=now()
      where id=r.id;
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail,metadata)
      values(r.practice_id,r.id,'suppressed',coalesce(v_permission->>'reason','Communication preference prevents automation.'),v_permission);
      v_suppressed:=v_suppressed+1;
      continue;
    end if;

    v_recipient:=case when v_channel='email' then nullif(trim(v_patient.primary_email),'') else nullif(trim(v_patient.primary_phone),'') end;
    if v_recipient is null then
      update public.communication_automation_job
      set status='suppressed',channel=v_channel,suppression_reason='No recipient address/number is available for the selected channel.',updated_at=now()
      where id=r.id;
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      values(r.practice_id,r.id,'suppressed','No recipient address/number is available for the selected channel.');
      v_suppressed:=v_suppressed+1;
      continue;
    end if;

    select * into v_template
    from public.communication_template
    where practice_id=r.practice_id and template_key=r.template_group_key||'_'||v_channel and active
      and approved_by is not null and approved_at is not null
    limit 1;
    if not found then
      update public.communication_automation_job
      set status='blocked',channel=v_channel,block_reason='Approved automation template is unavailable.',updated_at=now()
      where id=r.id;
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      values(r.practice_id,r.id,'blocked','Approved automation template is unavailable.');
      v_blocked:=v_blocked+1;
      continue;
    end if;

    v_context:=jsonb_build_object(
      'practice_name',coalesce(v_practice.name,'the practice'),
      'patient_first_name',coalesce(v_patient.first_name,'')
    );

    if r.source_entity_type='appointment' then
      select * into v_appointment from public.practice_appointment where id=r.source_entity_id and practice_id=r.practice_id;
      if not found or v_appointment.status not in ('booked','confirmed') or v_appointment.starts_at<=now() then
        update public.communication_automation_job
        set status='cancelled',suppression_reason='Appointment is no longer eligible for a reminder.',updated_at=now()
        where id=r.id;
        insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
        values(r.practice_id,r.id,'cancelled','Appointment is no longer eligible for a reminder.');
        continue;
      end if;
      v_context:=v_context||jsonb_build_object(
        'appointment_date',to_char(v_appointment.starts_at at time zone coalesce(v_practice.timezone,'Africa/Johannesburg'),'DD Mon YYYY'),
        'appointment_time',to_char(v_appointment.starts_at at time zone coalesce(v_practice.timezone,'Africa/Johannesburg'),'HH24:MI')
      );
    end if;

    if r.message_id is null then
      insert into public.communication_thread(practice_id,patient_id,thread_type,subject,status,created_by,last_activity_at)
      values(
        r.practice_id,r.patient_id,case when r.purpose='claims' then 'claim' else r.purpose end,
        nullif(private.render_communication_template(v_template.subject_template,v_context),''),
        'open',null,now()
      ) returning id into v_thread;

      insert into public.communication_message(thread_id,direction,channel,status,recipient,subject,body,contains_clinical_detail,created_by)
      values(
        v_thread,'outbound',v_channel,'draft',v_recipient,
        nullif(private.render_communication_template(v_template.subject_template,v_context),''),
        private.render_communication_template(v_template.body_template,v_context),
        false,null
      ) returning id into v_message;

      update public.communication_automation_job
      set message_id=v_message,channel=v_channel,status='materialized',block_reason=null,updated_at=now()
      where id=r.id;
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      values(r.practice_id,r.id,'materialized','Governed administrative message materialized from an approved template.');
      v_materialized:=v_materialized+1;
    else
      v_message:=r.message_id;
    end if;

    select * into v_route
    from public.practice_communication_route
    where practice_id=r.practice_id and channel=v_channel and environment=r.environment and enabled
    limit 1;
    if not found then
      update public.communication_automation_job
      set status='blocked',block_reason='No enabled provider route for this channel/environment.',updated_at=now()
      where id=r.id;
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      values(r.practice_id,r.id,'blocked','No enabled provider route for this channel/environment.');
      v_blocked:=v_blocked+1;
      continue;
    end if;

    select * into v_provider from public.communication_delivery_provider where id=v_route.provider_id;
    if not found or v_provider.status not in ('approved','production') or not v_provider.transport_ready then
      update public.communication_automation_job
      set status='blocked',block_reason='Configured provider is not approved and transport-ready.',updated_at=now()
      where id=r.id;
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      values(r.practice_id,r.id,'blocked','Configured provider is not approved and transport-ready.');
      v_blocked:=v_blocked+1;
      continue;
    end if;

    v_key:=encode(extensions.digest(v_message::text||':'||r.environment||':'||v_recipient,'sha256'),'hex');
    insert into public.communication_dispatch_request(message_id,provider_id,environment,status,idempotency_key,queued_by)
    values(v_message,v_provider.id,r.environment,'queued',v_key,null)
    on conflict (message_id,environment,idempotency_key)
    do update set status=case when public.communication_dispatch_request.status='failed' then 'queued' else public.communication_dispatch_request.status end
    returning id into v_dispatch;

    update public.communication_message set status='queued' where id=v_message and status in ('draft','failed');
    insert into public.communication_delivery_event(message_id,event_type,provider,detail)
    values(v_message,'queued',v_provider.display_name,'Queued automatically by PracticeCtrl governed communication automation.');

    update public.communication_automation_job set status='queued',block_reason=null,updated_at=now() where id=r.id;
    insert into public.communication_automation_event(practice_id,job_id,event_type,detail,metadata)
    values(r.practice_id,r.id,'queued','Queued through governed provider route.',jsonb_build_object('dispatch_request_id',v_dispatch,'provider_id',v_provider.id));
    v_queued:=v_queued+1;
  end loop;

  return jsonb_build_object(
    'scheduled',v_scheduled,'materialized',v_materialized,'queued',v_queued,
    'suppressed',v_suppressed,'blocked',v_blocked,'processed_at',now()
  );
end $function$
;
revoke all on function private.process_communication_automation(uuid) from public, anon;
CREATE OR REPLACE FUNCTION public.sync_communication_automation_job_from_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status is distinct from old.status then
    if new.status in ('sent','delivered','received') then
      update public.communication_automation_job
      set status='completed',updated_at=now(),block_reason=null
      where message_id=new.id and status not in ('completed','cancelled');
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      select j.practice_id,j.id,'completed','Message reached terminal successful state: '||new.status
      from public.communication_automation_job j where j.message_id=new.id;
    elsif new.status='failed' then
      update public.communication_automation_job
      set status='failed',updated_at=now(),block_reason='Delivery failed; see provider delivery events.'
      where message_id=new.id and status<>'cancelled';
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      select j.practice_id,j.id,'failed','Message delivery failed.'
      from public.communication_automation_job j where j.message_id=new.id;
    elsif new.status='cancelled' then
      update public.communication_automation_job
      set status='cancelled',updated_at=now()
      where message_id=new.id and status<>'completed';
      insert into public.communication_automation_event(practice_id,job_id,event_type,detail)
      select j.practice_id,j.id,'cancelled','Message was cancelled.'
      from public.communication_automation_job j where j.message_id=new.id;
    end if;
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.get_communication_readiness(p_practice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_rules int;
  v_enabled int;
  v_templates int;
  v_approved_templates int;
  v_routes int;
  v_staging_routes int;
  v_production_routes int;
  v_transport_ready int;
  v_health_ready int;
  v_blocked_jobs int;
  v_failed_jobs int;
  v_open_failures int;
  v_cron boolean;
  v_blockers jsonb:='[]'::jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
  ) then raise exception 'Active practice membership required'; end if;

  select count(*),count(*) filter (where enabled) into v_rules,v_enabled
  from public.communication_automation_rule where practice_id=p_practice_id;

  select count(*),count(*) filter (where active and approved_by is not null and approved_at is not null)
  into v_templates,v_approved_templates
  from public.communication_template where practice_id=p_practice_id;

  select count(*),
         count(*) filter (where environment='staging' and enabled),
         count(*) filter (where environment='production' and enabled)
  into v_routes,v_staging_routes,v_production_routes
  from public.practice_communication_route where practice_id=p_practice_id;

  select count(*) filter (where r.enabled and p.transport_ready and p.status in ('approved','production')),
         count(*) filter (where r.enabled and p.transport_ready and p.health_data_approved and p.status in ('approved','production'))
  into v_transport_ready,v_health_ready
  from public.practice_communication_route r
  join public.communication_delivery_provider p on p.id=r.provider_id
  where r.practice_id=p_practice_id;

  select count(*) filter (where status='blocked'),count(*) filter (where status='failed')
  into v_blocked_jobs,v_failed_jobs
  from public.communication_automation_job where practice_id=p_practice_id;

  select count(*) into v_open_failures
  from public.operations_work_item
  where practice_id=p_practice_id and category='communication'
    and status in ('open','in_progress','waiting','blocked');

  select exists(
    select 1 from cron.job
    where jobname='practicectrl-communication-automation-5m'
      and active
      and command='select private.process_communication_automation(null);'
  ) into v_cron;

  if v_rules=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_AUTOMATION_RULES','scope','configuration','message','No communication automation rules are configured.'));
  end if;
  if v_approved_templates=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_APPROVED_TEMPLATES','scope','configuration','message','No approved communication templates are available.'));
  end if;
  if not v_cron then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','AUTOMATION_SCHEDULER_INACTIVE','scope','staging','message','The communication automation scheduler is not active.'));
  end if;
  if v_staging_routes=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_STAGING_COMMUNICATION_ROUTE','scope','staging','message','No enabled staging communication provider route exists.'));
  end if;
  if v_transport_ready=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_TRANSPORT_READY_PROVIDER','scope','staging','message','No enabled route points to an approved, transport-ready communication provider.'));
  end if;
  if v_production_routes=0 then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_PRODUCTION_COMMUNICATION_ROUTE','scope','production','message','No enabled production communication provider route exists.'));
  end if;

  return jsonb_build_object(
    'generated_at',now(),
    'practice_id',p_practice_id,
    'automation_configured',v_rules>0,
    'scheduler_active',v_cron,
    'rules',jsonb_build_object('total',v_rules,'enabled',v_enabled),
    'templates',jsonb_build_object('total',v_templates,'approved',v_approved_templates),
    'routes',jsonb_build_object(
      'total_enabled',v_routes,
      'staging_enabled',v_staging_routes,
      'production_enabled',v_production_routes,
      'transport_ready',v_transport_ready,
      'health_data_ready',v_health_ready
    ),
    'exceptions',jsonb_build_object(
      'blocked_jobs',v_blocked_jobs,
      'failed_jobs',v_failed_jobs,
      'open_failure_work_items',v_open_failures
    ),
    'staging_transport_ready',v_staging_routes>0 and v_transport_ready>0,
    'production_transport_ready',v_production_routes>0 and v_transport_ready>0,
    'blockers',v_blockers
  );
end $function$
;
revoke all on function public.get_communication_readiness(uuid) from public, anon;
grant execute on function public.get_communication_readiness(uuid) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.set_patient_communication_preferences(p_practice_id uuid, p_patient_id uuid, p_preferred_channel text, p_appointment_reminders boolean, p_account_notifications boolean, p_clinical_notifications boolean, p_results_notifications boolean, p_marketing_messages boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid());
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_preferred_channel is not null and p_preferred_channel not in ('email','sms','whatsapp','phone') then
    raise exception 'Unsupported preferred channel';
  end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then
    raise exception 'Patient is not in this practice';
  end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('reception','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'This role cannot change patient communication preferences'; end if;

  insert into public.patient_communication_preference(
    patient_id,practice_id,preferred_channel,appointment_reminders,account_notifications,
    clinical_notifications,results_notifications,marketing_messages,updated_by,updated_at
  ) values(
    p_patient_id,p_practice_id,p_preferred_channel,p_appointment_reminders,p_account_notifications,
    p_clinical_notifications,p_results_notifications,p_marketing_messages,v_user,now()
  )
  on conflict (patient_id) do update set
    practice_id=excluded.practice_id,
    preferred_channel=excluded.preferred_channel,
    appointment_reminders=excluded.appointment_reminders,
    account_notifications=excluded.account_notifications,
    clinical_notifications=excluded.clinical_notifications,
    results_notifications=excluded.results_notifications,
    marketing_messages=excluded.marketing_messages,
    updated_by=v_user,
    updated_at=now();

  return jsonb_build_object(
    'patient_id',p_patient_id,'preferred_channel',p_preferred_channel,
    'appointment_reminders',p_appointment_reminders,'account_notifications',p_account_notifications,
    'clinical_notifications',p_clinical_notifications,'results_notifications',p_results_notifications,
    'marketing_messages',p_marketing_messages,'updated_at',now()
  );
end $function$
;
revoke all on function public.set_patient_communication_preferences(uuid,uuid,text,boolean,boolean,boolean,boolean,boolean) from public, anon;
grant execute on function public.set_patient_communication_preferences(uuid,uuid,text,boolean,boolean,boolean,boolean,boolean) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.record_communication_preference(p_practice_id uuid, p_patient_id uuid, p_channel text, p_purpose text, p_status text, p_source text DEFAULT 'staff'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid());
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_channel not in ('email','sms','whatsapp','phone') then raise exception 'Unsupported communication channel'; end if;
  if p_purpose not in ('administrative','appointment','billing','claims','clinical','marketing') then raise exception 'Unsupported communication purpose'; end if;
  if p_status not in ('unknown','allowed','restricted','withdrawn') then raise exception 'Unsupported preference status'; end if;
  if not exists(select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id) then
    raise exception 'Patient is not in this practice';
  end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'This role cannot record communication preferences'; end if;

  insert into public.communication_preference(
    practice_id,patient_id,channel,purpose,status,source,recorded_by,recorded_at
  ) values(
    p_practice_id,p_patient_id,p_channel,p_purpose,p_status,nullif(trim(coalesce(p_source,'')),''),v_user,now()
  )
  on conflict (patient_id,channel,purpose) do update set
    practice_id=excluded.practice_id,
    status=excluded.status,
    source=excluded.source,
    recorded_by=v_user,
    recorded_at=now();

  return jsonb_build_object(
    'patient_id',p_patient_id,'channel',p_channel,'purpose',p_purpose,
    'status',p_status,'recorded_by',v_user,'recorded_at',now()
  );
end $function$
;
revoke all on function public.record_communication_preference(uuid,uuid,text,text,text,text) from public, anon;
grant execute on function public.record_communication_preference(uuid,uuid,text,text,text,text) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.set_communication_automation_rule_enabled(p_rule_id uuid, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_rule public.communication_automation_rule%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_rule from public.communication_automation_rule where id=p_rule_id for update;
  if not found then raise exception 'Automation rule not found'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_rule.practice_id and m.active and m.role in ('practice_manager','system_admin')) then
    raise exception 'Practice manager or system administrator required';
  end if;
  update public.communication_automation_rule
  set enabled=p_enabled,
      approved_by=case when p_enabled then v_user else approved_by end,
      approved_at=case when p_enabled then now() else approved_at end,
      updated_at=now()
  where id=p_rule_id;
  return jsonb_build_object('rule_id',p_rule_id,'enabled',p_enabled,'approved_by',case when p_enabled then v_user else v_rule.approved_by end);
end $function$
;
revoke all on function public.set_communication_automation_rule_enabled(uuid,boolean) from public, anon;
grant execute on function public.set_communication_automation_rule_enabled(uuid,boolean) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.get_communication_automation_metrics(p_practice_id uuid, p_window_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user uuid:=(select auth.uid());
  v_start timestamptz:=now()-make_interval(days=>greatest(1,least(coalesce(p_window_days,30),365)));
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
  ) then raise exception 'Active practice membership required'; end if;

  return jsonb_build_object(
    'rules_total',(select count(*) from public.communication_automation_rule where practice_id=p_practice_id),
    'rules_enabled',(select count(*) from public.communication_automation_rule where practice_id=p_practice_id and enabled),
    'templates_total',(select count(*) from public.communication_template where practice_id=p_practice_id),
    'templates_approved',(select count(*) from public.communication_template where practice_id=p_practice_id and active and approved_by is not null and approved_at is not null),
    'jobs_scheduled',(select count(*) from public.communication_automation_job where practice_id=p_practice_id and status='scheduled'),
    'jobs_blocked',(select count(*) from public.communication_automation_job where practice_id=p_practice_id and status='blocked'),
    'jobs_suppressed',(select count(*) from public.communication_automation_job where practice_id=p_practice_id and status='suppressed' and updated_at>=v_start),
    'messages_queued',(select count(*) from public.communication_automation_job where practice_id=p_practice_id and status='queued' and updated_at>=v_start),
    'messages_sent',(select count(*) from public.communication_message m join public.communication_thread t on t.id=m.thread_id where t.practice_id=p_practice_id and m.direction='outbound' and m.status in ('sent','delivered') and coalesce(m.sent_at,m.created_at)>=v_start),
    'delivery_failures',(select count(*) from public.communication_message m join public.communication_thread t on t.id=m.thread_id where t.practice_id=p_practice_id and m.status='failed' and m.created_at>=v_start),
    'open_failure_work_items',(select count(*) from public.operations_work_item w where w.practice_id=p_practice_id and w.category='communication' and w.status in ('open','in_progress','waiting','blocked')),
    'provider_routes',(select count(*) from public.practice_communication_route r where r.practice_id=p_practice_id and r.enabled),
    'production_routes',(select count(*) from public.practice_communication_route r where r.practice_id=p_practice_id and r.environment='production' and r.enabled)
  );
end $function$
;
revoke all on function public.get_communication_automation_metrics(uuid,integer) from public, anon;
grant execute on function public.get_communication_automation_metrics(uuid,integer) to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.run_communication_automation_now(p_practice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare v_user uuid:=(select auth.uid()); v_result jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('practice_manager','system_admin')
  ) then raise exception 'Practice manager or system administrator required'; end if;
  select private.process_communication_automation(p_practice_id) into v_result;
  return v_result;
end $function$
;
revoke all on function public.run_communication_automation_now(uuid) from public, anon;
grant execute on function public.run_communication_automation_now(uuid) to authenticated, service_role;

create trigger communication_message_sync_automation_job after update of status on public.communication_message for each row execute function public.sync_communication_automation_job_from_message();
select cron.schedule('practicectrl-communication-automation-5m','*/5 * * * *','select private.process_communication_automation(null);');
commit;
