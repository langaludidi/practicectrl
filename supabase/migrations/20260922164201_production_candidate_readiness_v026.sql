create table if not exists public.release_validation_run (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  release_version text not null check (release_version ~ '^0\.[0-9]+\.[0-9]+(?:-[a-z0-9.]+)?$'),
  environment text not null default 'staging' check (environment in ('staging','production')),
  status text not null default 'planned' check (status in ('planned','running','passed','failed','blocked','cancelled')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  executed_by uuid not null references auth.users(id) on delete restrict,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.release_validation_step (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.release_validation_run(id) on delete cascade,
  practice_id uuid not null references public.practice(id) on delete cascade,
  step_key text not null,
  sequence smallint not null check (sequence between 1 and 100),
  label text not null,
  status text not null default 'pending' check (status in ('pending','passed','failed','blocked','skipped')),
  notes text,
  evidence jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(run_id,step_key)
);
create index if not exists release_validation_run_practice_created_idx on public.release_validation_run(practice_id,created_at desc);
create index if not exists release_validation_run_status_idx on public.release_validation_run(practice_id,status,created_at desc);
create index if not exists release_validation_run_executed_by_idx on public.release_validation_run(executed_by) where executed_by is not null;
create index if not exists release_validation_step_practice_status_idx on public.release_validation_step(practice_id,status);
create index if not exists release_validation_step_run_sequence_idx on public.release_validation_step(run_id,sequence);
create index if not exists release_validation_step_updated_by_idx on public.release_validation_step(updated_by) where updated_by is not null;
alter table public.release_validation_run enable row level security;
alter table public.release_validation_step enable row level security;
revoke all on table public.release_validation_run, public.release_validation_step from anon, authenticated;
grant select,insert,update on table public.release_validation_run, public.release_validation_step to authenticated;
create policy release_validation_run_read on public.release_validation_run for select to authenticated using (
 exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_run.practice_id and m.active and m.role in ('practice_manager','system_admin','auditor'))
 or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active)
);
create policy release_validation_run_insert on public.release_validation_run for insert to authenticated with check (
 ((select auth.jwt())->>'aal')='aal2' and executed_by=(select auth.uid()) and (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_run.practice_id and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active and po.role in ('platform_owner','platform_admin'))
 )
);
create policy release_validation_run_update on public.release_validation_run for update to authenticated using (
 ((select auth.jwt())->>'aal')='aal2' and (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_run.practice_id and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active and po.role in ('platform_owner','platform_admin'))
 )
) with check (
 ((select auth.jwt())->>'aal')='aal2' and (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_run.practice_id and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active and po.role in ('platform_owner','platform_admin'))
 )
);
create policy release_validation_step_read on public.release_validation_step for select to authenticated using (
 exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_step.practice_id and m.active and m.role in ('practice_manager','system_admin','auditor'))
 or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active)
);
create policy release_validation_step_insert on public.release_validation_step for insert to authenticated with check (
 ((select auth.jwt())->>'aal')='aal2' and (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_step.practice_id and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active and po.role in ('platform_owner','platform_admin'))
 )
);
create policy release_validation_step_update on public.release_validation_step for update to authenticated using (
 ((select auth.jwt())->>'aal')='aal2' and (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_step.practice_id and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active and po.role in ('platform_owner','platform_admin'))
 )
) with check (
 ((select auth.jwt())->>'aal')='aal2' and (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_validation_step.practice_id and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active and po.role in ('platform_owner','platform_admin'))
 )
);
create or replace function public.create_release_validation_run(p_practice_id uuid,p_release_version text default '0.26.0-dev.1')
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_run uuid; v_user uuid:=(select auth.uid());
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
 if not (
  exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=v_user and po.active and po.role in ('platform_owner','platform_admin'))
 ) then raise exception 'Release validation manager role required'; end if;
 insert into public.release_validation_run(practice_id,release_version,environment,status,executed_by)
 values(p_practice_id,p_release_version,'staging','running',v_user) returning id into v_run;
 insert into public.release_validation_step(run_id,practice_id,step_key,sequence,label,status) values
 (v_run,p_practice_id,'production_build',1,'Dependency-restored Next.js production build','pending'),
 (v_run,p_practice_id,'security_advisors',2,'Security and performance advisor review','pending'),
 (v_run,p_practice_id,'tenant_access',3,'Tenant isolation, role access and MFA','pending'),
 (v_run,p_practice_id,'appointment',4,'Appointment booking and check-in','pending'),
 (v_run,p_practice_id,'patient_intake',5,'Patient intake, identity reconciliation and consent','pending'),
 (v_run,p_practice_id,'clinical_encounter',6,'Clinical encounter and signed documentation','pending'),
 (v_run,p_practice_id,'code10',7,'Code10 coding, validation and clinical handoff','pending'),
 (v_run,p_practice_id,'billing_preflight',8,'Invoice creation, payer resolution and claim pre-flight','pending'),
 (v_run,p_practice_id,'sandbox_claim',9,'Sandbox claim submission and response','pending'),
 (v_run,p_practice_id,'era_reconciliation',10,'ERA/remittance receipt and reconciliation','pending'),
 (v_run,p_practice_id,'revenue_followup',11,'Revenue Integrity exception and follow-up queue','pending'),
 (v_run,p_practice_id,'audit_evidence',12,'Audit trail, evidence capture and release sign-off','pending');
 return v_run;
end $$;
create or replace function public.update_release_validation_step(p_step_id uuid,p_status text,p_notes text default null,p_evidence jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_run uuid; v_practice uuid; v_user uuid:=(select auth.uid()); v_pending int; v_failed int; v_blocked int; v_skipped int; v_final text;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
 if p_status not in ('pending','passed','failed','blocked','skipped') then raise exception 'Unsupported validation status'; end if;
 select run_id,practice_id into v_run,v_practice from public.release_validation_step where id=p_step_id;
 if v_run is null then raise exception 'Validation step not found'; end if;
 if not (
  exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_practice and m.active and m.role in ('practice_manager','system_admin'))
  or exists(select 1 from public.platform_operator po where po.user_id=v_user and po.active and po.role in ('platform_owner','platform_admin'))
 ) then raise exception 'Release validation manager role required'; end if;
 update public.release_validation_step set status=p_status,notes=nullif(btrim(p_notes),''),
 evidence=coalesce(p_evidence,'{}'::jsonb),updated_by=v_user,updated_at=now() where id=p_step_id;
 select count(*) filter(where status='pending'),count(*) filter(where status='failed'),count(*) filter(where status='blocked'),count(*) filter(where status='skipped')
 into v_pending,v_failed,v_blocked,v_skipped from public.release_validation_step where run_id=v_run;
 v_final:=case when v_failed>0 then 'failed' when v_blocked>0 then 'blocked' when v_pending=0 and v_skipped=0 then 'passed' else 'running' end;
 update public.release_validation_run set status=v_final,completed_at=case when v_final in ('passed','failed','blocked') then now() else null end,updated_at=now() where id=v_run;
 return jsonb_build_object('run_id',v_run,'status',v_final,'pending',v_pending,'failed',v_failed,'blocked',v_blocked,'skipped',v_skipped);
end $$;
revoke all on function public.create_release_validation_run(uuid,text) from public,anon;
revoke all on function public.update_release_validation_step(uuid,text,text,jsonb) from public,anon;
grant execute on function public.create_release_validation_run(uuid,text) to authenticated;
grant execute on function public.update_release_validation_step(uuid,text,text,jsonb) to authenticated;
create or replace function public.get_practicectrl_release_readiness(p_practice_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=public,storage,pg_temp as $$
declare
 v_user uuid:=(select auth.uid());
 v_staff int; v_origin boolean; v_mit int; v_codes bigint; v_schemes bigint; v_options bigint;
 v_open bigint; v_open_covered bigint; v_restricted bigint; v_restricted_covered bigint;
 v_sandbox_caps bigint; v_sandbox_connections bigint; v_prod_caps bigint; v_prod_connections bigint;
 v_waiting bigint; v_pending_sources bigint; v_rls boolean; v_buckets boolean; v_unsafe bigint;
 v_latest_run jsonb; v_uat_passed boolean:=false; v_staging_ready boolean; v_production_ready boolean; v_blockers jsonb:='[]'::jsonb;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if not (
  exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practice_manager','system_admin','auditor'))
  or exists(select 1 from public.platform_operator po where po.user_id=v_user and po.active)
 ) then raise exception 'Privileged PracticeCtrl role required'; end if;
 select count(*) into v_staff from public.practice_staff_member where practice_id=p_practice_id and active;
 select exists(select 1 from public.practice_app_origin where practice_id=p_practice_id and environment='staging' and active) into v_origin;
 select count(*) into v_mit from public.coding_source_release where authority='NDOH' and source_name='ICD-10 Master Industry Table' and status='active';
 select count(*) into v_codes from public.sa_icd10_code c join public.coding_source_release r on r.id=c.source_release_id where r.status='active' and r.authority='NDOH';
 select count(*) into v_schemes from public.medical_scheme;
 select count(*) into v_options from public.medical_scheme_option where benefit_year=2026;
 select count(*) into v_open from public.medical_scheme where scheme_type='open';
 select count(distinct o.medical_scheme_id) into v_open_covered from public.medical_scheme_option o join public.medical_scheme m on m.id=o.medical_scheme_id where o.benefit_year=2026 and m.scheme_type='open';
 select count(*) into v_restricted from public.medical_scheme where scheme_type='restricted';
 select count(distinct o.medical_scheme_id) into v_restricted_covered from public.medical_scheme_option o join public.medical_scheme m on m.id=o.medical_scheme_id where o.benefit_year=2026 and m.scheme_type='restricted';
 select count(*) into v_sandbox_caps from public.integration_adapter_capability a join public.integration_provider p on p.id=a.provider_id where a.executable_sandbox and p.slug='practicectrl-sandbox';
 select count(*) into v_sandbox_connections from public.practice_integration_connection c join public.integration_provider p on p.id=c.provider_id where c.practice_id=p_practice_id and c.environment='sandbox' and c.status in ('sandbox_active','active','production_ready') and p.slug='practicectrl-sandbox';
 select count(*) into v_prod_caps from public.integration_adapter_capability a join public.integration_provider p on p.id=a.provider_id where a.executable_production and p.slug<>'practicectrl-sandbox';
 select count(*) into v_prod_connections from public.practice_integration_connection where practice_id=p_practice_id and environment='production' and status in ('production_ready','active');
 select count(*) into v_waiting from public.integration_requirement where status='waiting_external';
 select count(*) into v_pending_sources from public.source_dataset_release where status='pending_review';
 select (count(*)=5 and coalesce(bool_and(public=false),false)) into v_buckets from storage.buckets where id in ('switch-payloads','governed-source-files','practice-import-files','patient-intake-files','payer-contract-files');
 select coalesce(bool_and(c.relrowsecurity),false) into v_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('crm_patient','clinical_note','billing_invoice','claim_record','remittance_advice','release_validation_run','release_validation_step');
 select count(*) into v_unsafe from public.practice_assist_policy where practice_id=p_practice_id and enabled and allowed_data_class='health_special' and (retain_raw_input or retain_raw_output);
 select jsonb_build_object('id',r.id,'release_version',r.release_version,'environment',r.environment,'status',r.status,'started_at',r.started_at,'completed_at',r.completed_at,
   'passed_steps',(select count(*) from public.release_validation_step s where s.run_id=r.id and s.status='passed'),
   'total_steps',(select count(*) from public.release_validation_step s where s.run_id=r.id))
 into v_latest_run from public.release_validation_run r where r.practice_id=p_practice_id order by r.created_at desc limit 1;
 v_uat_passed:=coalesce(v_latest_run->>'status','')='passed';
 v_staging_ready:=v_staff>0 and v_origin and v_mit=1 and v_codes>0 and v_schemes>0 and v_options>0 and v_open_covered=v_open and v_sandbox_caps>0 and v_sandbox_connections>0 and v_rls and v_buckets and v_unsafe=0;
 v_production_ready:=v_staging_ready and v_uat_passed and v_restricted_covered=v_restricted and v_prod_caps>0 and v_prod_connections>0 and v_waiting=0 and v_pending_sources=0;
 if v_staff=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_ACTIVE_STAFF','scope','staging','message','No active tenant staff are enrolled.')); end if;
 if not v_origin then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_STAGING_ORIGIN','scope','staging','message','No PracticeCtrl staging application origin is configured.')); end if;
 if v_mit<>1 or v_codes=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','CODE10_SOURCE_INACTIVE','scope','staging','message','The governed South African ICD-10 MIT is not active with usable codes.')); end if;
 if v_open_covered<>v_open then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','OPEN_SCHEME_OPTIONS_INCOMPLETE','scope','staging','message','Not every open medical scheme has a governed 2026 option master.')); end if;
 if v_sandbox_caps=0 or v_sandbox_connections=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SANDBOX_GATEWAY_NOT_READY','scope','staging','message','Sandbox payer integration is not executable for this practice.')); end if;
 if not v_rls or not v_buckets or v_unsafe>0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SECURITY_GATE','scope','staging','message','One or more sensitive-data security controls are not ready.')); end if;
 if not v_uat_passed then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','UAT_NOT_PASSED','scope','production','message','The latest 12-step release validation run has not passed.')); end if;
 if v_restricted_covered<>v_restricted then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','RESTRICTED_SCHEME_OPTIONS_INCOMPLETE','scope','production','message','The 2026 restricted-scheme option master is incomplete.')); end if;
 if v_prod_caps=0 or v_prod_connections=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PRODUCTION_SWITCH_NOT_CONNECTED','scope','production','message','No accredited external production claims route is executable and connected.')); end if;
 if v_waiting>0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','EXTERNAL_REQUIREMENTS_WAITING','scope','production','message',v_waiting||' external integration requirements are still waiting.')); end if;
 if v_pending_sources>0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SOURCE_RELEASES_PENDING','scope','production','message',v_pending_sources||' governed source releases still require review.')); end if;
 return jsonb_build_object(
  'generated_at',now(),'release_target','0.26.0-dev.1','staging_ready',v_staging_ready,'production_ready',v_production_ready,
  'staff',jsonb_build_object('active_count',v_staff,'ready',v_staff>0),
  'deployment',jsonb_build_object('staging_origin_configured',v_origin,'ready',v_origin),
  'code10',jsonb_build_object('active_ndoh_mit_releases',v_mit,'active_codes',v_codes,'ready',v_mit=1 and v_codes>0),
  'payer_registry',jsonb_build_object('schemes',v_schemes,'options_2026',v_options,'open_total',v_open,'open_covered',v_open_covered,'restricted_total',v_restricted,'restricted_covered',v_restricted_covered,'staging_ready',v_open_covered=v_open,'production_ready',v_restricted_covered=v_restricted),
  'switching',jsonb_build_object('sandbox_capabilities',v_sandbox_caps,'sandbox_connections',v_sandbox_connections,'sandbox_ready',v_sandbox_caps>0 and v_sandbox_connections>0,'external_production_capabilities',v_prod_caps,'production_connections',v_prod_connections,'production_ready',v_prod_caps>0 and v_prod_connections>0),
  'sources',jsonb_build_object('pending_review',v_pending_sources,'ready',v_pending_sources=0),
  'external_requirements',jsonb_build_object('waiting_external',v_waiting,'ready',v_waiting=0),
  'security',jsonb_build_object('sensitive_rls_enabled',v_rls,'private_storage_buckets',v_buckets,'unsafe_health_assist_policies',v_unsafe,'ready',v_rls and v_buckets and v_unsafe=0),
  'latest_validation_run',v_latest_run,'blockers',v_blockers);
end $$;
revoke all on function public.get_practicectrl_release_readiness(uuid) from public,anon;
grant execute on function public.get_practicectrl_release_readiness(uuid) to authenticated;
