-- Practice Configuration V1. Apply to an isolated development branch before staging.
-- Existing practice, locations, practitioners, appointment types and payer contracts remain authoritative.
create table public.practice_operating_config (
 practice_id uuid primary key references public.practice(id) on delete cascade,
 appointment_source text not null default 'PMS' check (appointment_source = 'PMS'),
 default_appointment_minutes integer not null default 30 check (default_appointment_minutes between 5 and 480),
 cancellation_notice_hours integer not null default 24 check (cancellation_notice_hours between 0 and 720),
 require_patient_contact boolean not null default true,
 require_scheme_membership boolean not null default false,
 require_identity_review boolean not null default true,
 default_currency text not null default 'ZAR' check (default_currency ~ '^[A-Z]{3}$'),
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default now()
);

create table public.practice_payer_relationship (
 id uuid primary key default gen_random_uuid(),
 practice_id uuid not null references public.practice(id),
 medical_scheme_id uuid not null references public.medical_scheme(id),
 status text not null default 'draft' check (status in ('draft','in_review','approved','active','retired')),
 relationship_type text not null check (relationship_type in ('contracted','non_contracted','unknown')),
 accepted boolean not null default true,
 network_status text,
 default_administrator text,
 submission_route text,
 effective_from date not null,
 effective_to date,
 version integer not null default 1 check (version > 0),
 notes text,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint practice_payer_dates check (effective_to is null or effective_to >= effective_from),
 constraint practice_payer_approved check (status not in ('approved','active') or (approved_by is not null and approved_at is not null)),
 unique (practice_id, medical_scheme_id, version)
);
create index practice_payer_relationship_lookup on public.practice_payer_relationship(practice_id,medical_scheme_id,effective_from);
create unique index practice_payer_one_active on public.practice_payer_relationship(practice_id,medical_scheme_id) where status='active';

create table public.practice_policy (
 id uuid primary key default gen_random_uuid(),
 practice_id uuid not null references public.practice(id),
 policy_key text not null check (policy_key ~ '^[a-z0-9_]{3,80}$'),
 title text not null check (length(btrim(title)) > 0),
 category text not null,
 sop text not null,
 owner_role public.practice_staff_role,
 trigger_kind text,
 conditions jsonb not null default '{}'::jsonb check (jsonb_typeof(conditions) = 'object'),
 required_evidence jsonb not null default '[]'::jsonb check (jsonb_typeof(required_evidence) = 'array'),
 due_hours integer check (due_hours >= 0),
 blocking boolean not null default false,
 escalation_role public.practice_staff_role,
 status text not null default 'draft' check (status in ('draft','in_review','approved','scheduled','active','retired')),
 version integer not null default 1 check (version > 0),
 effective_from date not null,
 effective_to date,
 source_document_id uuid,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint practice_policy_dates check (effective_to is null or effective_to >= effective_from),
 constraint practice_policy_approved check (status not in ('approved','scheduled','active') or (approved_by is not null and approved_at is not null)),
 unique (practice_id, policy_key, version)
);
create index practice_policy_effective on public.practice_policy(practice_id,policy_key,effective_from);
create unique index practice_policy_one_active on public.practice_policy(practice_id,policy_key) where status='active';

create table public.practice_configuration_event (
 id bigint generated always as identity primary key,
 practice_id uuid not null references public.practice(id),
 entity_type text not null,
 entity_id text not null,
 action text not null,
 before_value jsonb,
 after_value jsonb,
 actor_user_id uuid,
 created_at timestamptz not null default now()
);
create index practice_configuration_event_recent on public.practice_configuration_event(practice_id,created_at desc);

-- All mutations of new configuration records have an immutable, tenant-scoped audit trail.
create function public.audit_practice_configuration() returns trigger language plpgsql
 security definer set search_path = public, pg_temp as $$
begin
 insert into public.practice_configuration_event(practice_id,entity_type,entity_id,action,before_value,after_value,actor_user_id)
 values (coalesce(new.practice_id,old.practice_id),tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id',coalesce(new.practice_id,old.practice_id)::text),
         tg_op,case when tg_op='INSERT' then null else to_jsonb(old)-'banking_details' end,
         case when tg_op='DELETE' then null else to_jsonb(new)-'banking_details' end,auth.uid());
 return coalesce(new,old);
end $$;
create trigger audit_operating_config after insert or update or delete on public.practice_operating_config
 for each row execute function public.audit_practice_configuration();
create trigger audit_payer_relationship after insert or update or delete on public.practice_payer_relationship
 for each row execute function public.audit_practice_configuration();
create trigger audit_policy after insert or update or delete on public.practice_policy
 for each row execute function public.audit_practice_configuration();
create trigger audit_billing_profile after insert or update on public.practice_billing_profile
 for each row execute function public.audit_practice_configuration();
create trigger audit_practice_location after insert or update on public.practice_location
 for each row execute function public.audit_practice_configuration();
create trigger audit_practitioner_profile after insert or update on public.practitioner_profile
 for each row execute function public.audit_practice_configuration();
create trigger audit_appointment_type after insert or update on public.appointment_type
 for each row execute function public.audit_practice_configuration();

-- Historical versions are append-only once reviewed. Operational changes create a new version.
create function public.guard_practice_configuration_version() returns trigger language plpgsql
 set search_path = public, pg_temp as $$
begin
 if tg_op='DELETE' then raise exception 'Configuration history cannot be deleted'; end if;
 if tg_op='INSERT' then
  if new.status <> 'draft' or new.approved_by is not null or new.approved_at is not null
  then raise exception 'New configuration must start as an unapproved draft'; end if;
  new.created_by:=auth.uid();
  return new;
 end if;
 if tg_table_name='practice_policy' and new.status in ('scheduled','active')
 then raise exception 'Policy execution is not connected to Operations; keep the approved policy inactive'; end if;
 if new.practice_id is distinct from old.practice_id or new.version is distinct from old.version or
    new.created_by is distinct from old.created_by or
    (tg_table_name='practice_payer_relationship' and to_jsonb(new)->>'medical_scheme_id' is distinct from to_jsonb(old)->>'medical_scheme_id') or
    (tg_table_name='practice_policy' and to_jsonb(new)->>'policy_key' is distinct from to_jsonb(old)->>'policy_key')
 then raise exception 'Configuration identity and version cannot change'; end if;
 if new.status is distinct from old.status then
  if not ((old.status='draft' and new.status='in_review')
    or (old.status='in_review' and new.status='approved')
    or (old.status='approved' and new.status in ('scheduled','active','retired'))
    or (old.status='scheduled' and new.status in ('active','retired'))
    or (old.status='active' and new.status='retired'))
  then raise exception 'Invalid configuration lifecycle transition'; end if;
 end if;
 if new.status in ('approved','scheduled','active') and (new.approved_by is null or new.approved_at is null)
 then raise exception 'An approver and approval time are required'; end if;
 if new.status in ('draft','in_review') and (new.approved_by is not null or new.approved_at is not null)
 then raise exception 'Unapproved configuration cannot contain approval metadata'; end if;
 if old.status='in_review' and new.status='approved' and
   (new.approved_by is distinct from auth.uid() or abs(extract(epoch from (new.approved_at-now())))>120)
 then raise exception 'Approval must record the current reviewer and time'; end if;
 if old.status in ('approved','scheduled','active','retired') then
   if to_jsonb(new) - 'status' - 'updated_at' is distinct from to_jsonb(old) - 'status' - 'updated_at'
      then raise exception 'Approved configuration must be versioned'; end if;
 end if;
 if old.status='retired' then raise exception 'Retired configuration cannot change'; end if;
 return new;
end $$;
create trigger guard_payer_relationship before insert or update or delete on public.practice_payer_relationship
 for each row execute function public.guard_practice_configuration_version();
create trigger guard_policy before insert or update or delete on public.practice_policy
 for each row execute function public.guard_practice_configuration_version();

create function public.guard_operating_config_delete() returns trigger language plpgsql
 set search_path = public, pg_temp as $$ begin raise exception 'Operating configuration cannot be deleted'; end $$;
create trigger guard_operating_config_delete before delete on public.practice_operating_config
 for each row execute function public.guard_operating_config_delete();

alter table public.practice_operating_config enable row level security;
alter table public.practice_payer_relationship enable row level security;
alter table public.practice_policy enable row level security;
alter table public.practice_configuration_event enable row level security;

create policy operating_config_read on public.practice_operating_config for select to authenticated using
 (exists(select 1 from public.practice_staff_member m where m.practice_id=practice_operating_config.practice_id and m.user_id=(select auth.uid()) and m.active));
create policy operating_config_write on public.practice_operating_config for all to authenticated using
 ((select auth.jwt()->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.practice_id=practice_operating_config.practice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin')))
 with check ((select auth.jwt()->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.practice_id=practice_operating_config.practice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin')));
create policy payer_relationship_read on public.practice_payer_relationship for select to authenticated using
 (exists(select 1 from public.practice_staff_member m where m.practice_id=practice_payer_relationship.practice_id and m.user_id=(select auth.uid()) and m.active));
create policy payer_relationship_write on public.practice_payer_relationship for all to authenticated using
 ((select auth.jwt()->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.practice_id=practice_payer_relationship.practice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin')))
 with check ((select auth.jwt()->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.practice_id=practice_payer_relationship.practice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin')));
create policy practice_policy_read on public.practice_policy for select to authenticated using
 (exists(select 1 from public.practice_staff_member m where m.practice_id=practice_policy.practice_id and m.user_id=(select auth.uid()) and m.active));
create policy practice_policy_write on public.practice_policy for all to authenticated using
 ((select auth.jwt()->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.practice_id=practice_policy.practice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin')))
 with check ((select auth.jwt()->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.practice_id=practice_policy.practice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin')));
create policy configuration_event_read on public.practice_configuration_event for select to authenticated using
 (exists(select 1 from public.practice_staff_member m where m.practice_id=practice_configuration_event.practice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin','auditor')));

grant select,insert,update on public.practice_operating_config,public.practice_payer_relationship,public.practice_policy to authenticated;
grant select on public.practice_configuration_event to authenticated;
revoke all on function public.audit_practice_configuration() from public,anon,authenticated;
revoke all on function public.guard_practice_configuration_version() from public,anon,authenticated;
revoke all on function public.guard_operating_config_delete() from public,anon,authenticated;

-- Existing practice has no general UPDATE policy. A narrow RPC handles identity and branding.
create function public.update_practice_identity(p_practice_id uuid,p_name text,p_legal_name text,p_timezone text,p_brand_name text,p_logo_url text)
 returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_before jsonb; v_after jsonb;
begin
 if (select auth.jwt()->>'aal') is distinct from 'aal2' or not exists(
   select 1 from public.practice_staff_member m where m.practice_id=p_practice_id
   and m.user_id=(select auth.uid()) and m.active and m.role in ('practice_manager','system_admin'))
 then raise exception 'Practice administrator with MFA required'; end if;
 if nullif(btrim(p_name),'') is null or length(p_name)>160 or length(coalesce(p_legal_name,''))>160
   or length(coalesce(p_brand_name,''))>160 or length(p_timezone)>100
   or (nullif(btrim(coalesce(p_logo_url,'')),'') is not null and
        (p_logo_url !~ '^https://[^[:space:]]+$' or length(p_logo_url)>500))
 then raise exception 'Invalid practice identity'; end if;
 if not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'Invalid timezone'; end if;
 select jsonb_build_object('name',name,'legal_name',legal_name,'timezone',timezone,'branding',branding)
 into v_before from public.practice where id=p_practice_id for update;
 if v_before is null then raise exception 'Practice not found'; end if;
 update public.practice set name=btrim(p_name),legal_name=nullif(btrim(p_legal_name),''),timezone=p_timezone,
   branding=jsonb_set(jsonb_set(coalesce(branding,'{}'::jsonb),'{display_name}',
     to_jsonb(coalesce(nullif(btrim(p_brand_name),''),btrim(p_name)))),
     '{logo_url}',to_jsonb(nullif(btrim(coalesce(p_logo_url,'')),'')))
 where id=p_practice_id;
 select jsonb_build_object('name',name,'legal_name',legal_name,'timezone',timezone,'branding',branding)
 into v_after from public.practice where id=p_practice_id;
 insert into public.practice_configuration_event(practice_id,entity_type,entity_id,action,before_value,after_value,actor_user_id)
 values(p_practice_id,'practice',p_practice_id::text,'UPDATE',v_before,v_after,auth.uid());
end $$;
revoke all on function public.update_practice_identity(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.update_practice_identity(uuid,text,text,text,text,text) to authenticated;

-- Read-only, service-date simulator. Uses the existing financial resolver and adds provenance;
-- transactional rule-resolution changes belong to Effective Rules Engine V2.
create function public.simulate_practice_payer_rule(p_practice_id uuid,p_practitioner_id uuid,p_scheme_id uuid,
 p_option_id uuid,p_code_system text,p_code text,p_service_date date,p_reference_amount numeric,
 p_charged_amount numeric,p_quantity numeric default 1) returns jsonb
 language plpgsql stable security invoker set search_path=public,pg_temp as $$
declare v_result jsonb; v_rule public.payer_billing_rule%rowtype; v_contract public.payer_contract%rowtype;
 v_requirements jsonb;
begin
 if not exists(select 1 from public.practice_staff_member m where m.practice_id=p_practice_id
   and m.user_id=(select auth.uid()) and m.active) then raise exception 'Practice access required'; end if;
 v_result:=public.resolve_payer_billing_rule(p_practice_id,p_practitioner_id,p_scheme_id,p_option_id,p_code_system,
   p_code,p_service_date,p_reference_amount,p_charged_amount,p_quantity);
 if nullif(v_result->>'applied_rule_id','') is not null then
  select * into v_rule from public.payer_billing_rule where id=(v_result->>'applied_rule_id')::uuid
    and (practice_id=p_practice_id or practice_id is null);
  if v_rule.contract_id is not null then
   select * into v_contract from public.payer_contract where id=v_rule.contract_id and practice_id=p_practice_id;
  end if;
 end if;
 select coalesce(jsonb_agg(req.item || jsonb_build_object(
   'version',r.version,'effective_from',r.effective_from,'effective_to',r.effective_to,
   'source_document_id',r.source_document_id) order by req.rank),'[]'::jsonb)
 into v_requirements from jsonb_array_elements(coalesce(v_result->'requirements','[]'::jsonb)) with ordinality req(item,rank)
 left join public.payer_billing_rule r on r.id=(req.item->>'rule_id')::uuid
   and (r.practice_id is null or r.practice_id=p_practice_id);
 return v_result || jsonb_build_object('requirements',v_requirements,'decision_trace',jsonb_build_object(
   'resolver','resolve_payer_billing_rule','service_date',p_service_date,'code_system',p_code_system,'code',p_code,
   'rule_id',v_rule.id,'rule_scope',v_rule.rule_scope,'rule_version',v_rule.version,
   'rule_effective_from',v_rule.effective_from,'rule_effective_to',v_rule.effective_to,
   'source_document_id',v_rule.source_document_id,'contract_id',v_contract.id,
   'contract_version',v_contract.version,'contract_effective_from',v_contract.effective_from,
   'contract_effective_to',v_contract.effective_to,
   'review_required',v_rule.id is null));
end $$;
revoke all on function public.simulate_practice_payer_rule(uuid,uuid,uuid,uuid,text,text,date,numeric,numeric,numeric) from public,anon;
grant execute on function public.simulate_practice_payer_rule(uuid,uuid,uuid,uuid,text,text,date,numeric,numeric,numeric) to authenticated;
