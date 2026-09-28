
create or replace function public.get_practicectrl_release_readiness(p_practice_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,storage,pg_temp
as $$
declare
  v_user uuid:=(select auth.uid());
  v_staff int; v_origin boolean; v_mit int; v_codes bigint; v_schemes bigint; v_options bigint;
  v_open bigint; v_open_covered bigint; v_restricted bigint; v_restricted_covered bigint;
  v_sandbox_caps bigint; v_sandbox_connections bigint; v_prod_caps bigint; v_prod_connections bigint;
  v_waiting bigint; v_pending_sources bigint; v_rls boolean; v_buckets boolean; v_unsafe bigint;
  v_latest_run jsonb; v_uat_passed boolean:=false;
  v_latest_probe jsonb; v_probe_passed boolean:=false;
  v_staging_ready boolean; v_production_ready boolean; v_blockers jsonb:='[]'::jsonb;
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
  select count(distinct o.medical_scheme_id) into v_open_covered from public.medical_scheme_option o join public.medical_scheme m on m.id=o.medical_scheme_id where o.benefit_year=2026 and o.approval_status='approved' and m.scheme_type='open';
  select count(*) into v_restricted from public.medical_scheme where scheme_type='restricted';
  select count(distinct o.medical_scheme_id) into v_restricted_covered from public.medical_scheme_option o join public.medical_scheme m on m.id=o.medical_scheme_id where o.benefit_year=2026 and o.approval_status='approved' and m.scheme_type='restricted';

  select count(*) into v_sandbox_caps from public.integration_adapter_capability a join public.integration_provider p on p.id=a.provider_id where a.executable_sandbox and p.slug='practicectrl-sandbox';
  select count(*) into v_sandbox_connections from public.practice_integration_connection c join public.integration_provider p on p.id=c.provider_id where c.practice_id=p_practice_id and c.environment='sandbox' and c.status in ('sandbox_active','active','production_ready') and p.slug='practicectrl-sandbox';
  select count(*) into v_prod_caps from public.integration_adapter_capability a join public.integration_provider p on p.id=a.provider_id where a.executable_production and p.slug<>'practicectrl-sandbox';
  select count(*) into v_prod_connections from public.practice_integration_connection where practice_id=p_practice_id and environment='production' and status in ('production_ready','active');
  select count(*) into v_waiting from public.integration_requirement where status='waiting_external';
  select count(*) into v_pending_sources from public.source_dataset_release where status='pending_review';

  select (count(*)=5 and coalesce(bool_and(public=false),false)) into v_buckets from storage.buckets where id in ('switch-payloads','governed-source-files','practice-import-files','patient-intake-files','payer-contract-files');
  select coalesce(bool_and(c.relrowsecurity),false) into v_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('crm_patient','clinical_note','billing_invoice','claim_record','remittance_advice','release_validation_run','release_validation_step','release_probe_snapshot');
  select count(*) into v_unsafe from public.practice_assist_policy where practice_id=p_practice_id and enabled and allowed_data_class='health_special' and (retain_raw_input or retain_raw_output);

  select jsonb_build_object('id',r.id,'release_version',r.release_version,'environment',r.environment,'status',r.status,'started_at',r.started_at,'completed_at',r.completed_at,
    'passed_steps',(select count(*) from public.release_validation_step s where s.run_id=r.id and s.status='passed'),
    'total_steps',(select count(*) from public.release_validation_step s where s.run_id=r.id))
  into v_latest_run from public.release_validation_run r where r.practice_id=p_practice_id order by r.created_at desc limit 1;
  v_uat_passed:=coalesce(v_latest_run->>'status','')='passed';

  select jsonb_build_object('id',p.id,'release_version',p.release_version,'probe_version',p.probe_version,'all_passed',p.all_passed,'passed_count',p.passed_count,'failed_count',p.failed_count,'created_at',p.created_at)
  into v_latest_probe from public.release_probe_snapshot p
  where p.practice_id=p_practice_id and p.release_version='0.27.0-dev.1'
  order by p.created_at desc limit 1;
  v_probe_passed:=coalesce((v_latest_probe->>'all_passed')::boolean,false);

  v_staging_ready := v_staff>0 and v_origin and v_mit=1 and v_codes>0 and v_schemes>0 and v_options>0 and v_open_covered=v_open and v_sandbox_caps>0 and v_sandbox_connections>0 and v_rls and v_buckets and v_unsafe=0 and v_probe_passed;
  v_production_ready := v_staging_ready and v_uat_passed and v_restricted_covered=v_restricted and v_prod_caps>0 and v_prod_connections>0 and v_waiting=0 and v_pending_sources=0;

  if v_staff=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_ACTIVE_STAFF','scope','staging','message','No active tenant staff are enrolled.')); end if;
  if not v_origin then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','NO_STAGING_ORIGIN','scope','staging','message','No PracticeCtrl staging application origin is configured.')); end if;
  if v_mit<>1 or v_codes=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','CODE10_SOURCE_INACTIVE','scope','staging','message','The governed South African ICD-10 MIT is not active with usable codes.')); end if;
  if v_open_covered<>v_open then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','OPEN_SCHEME_OPTIONS_INCOMPLETE','scope','staging','message','Not every open medical scheme has a governed approved 2026 option master.')); end if;
  if v_sandbox_caps=0 or v_sandbox_connections=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SANDBOX_GATEWAY_NOT_READY','scope','staging','message','Sandbox payer integration is not executable for this practice.')); end if;
  if not v_rls or not v_buckets or v_unsafe>0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SECURITY_GATE','scope','staging','message','One or more sensitive-data security controls are not ready.')); end if;
  if not v_probe_passed then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','AUTOMATED_PROBE_NOT_PASSED','scope','staging','message','The current v0.27 automated staging probe has not passed.')); end if;
  if not v_uat_passed then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','UAT_NOT_PASSED','scope','production','message','The latest 12-step release validation run has not passed.')); end if;
  if v_restricted_covered<>v_restricted then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','RESTRICTED_SCHEME_OPTIONS_INCOMPLETE','scope','production','message','The 2026 restricted-scheme option master is incomplete.')); end if;
  if v_prod_caps=0 or v_prod_connections=0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PRODUCTION_SWITCH_NOT_CONNECTED','scope','production','message','No accredited external production claims route is executable and connected.')); end if;
  if v_waiting>0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','EXTERNAL_REQUIREMENTS_WAITING','scope','production','message',v_waiting||' external integration requirements are still waiting.')); end if;
  if v_pending_sources>0 then v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SOURCE_RELEASES_PENDING','scope','production','message',v_pending_sources||' governed source releases still require review.')); end if;

  return jsonb_build_object(
    'generated_at',now(),
    'release_target','0.27.0-dev.1',
    'staging_ready',v_staging_ready,
    'production_ready',v_production_ready,
    'staff',jsonb_build_object('active_count',v_staff,'ready',v_staff>0),
    'deployment',jsonb_build_object('staging_origin_configured',v_origin,'ready',v_origin),
    'code10',jsonb_build_object('active_ndoh_mit_releases',v_mit,'active_codes',v_codes,'ready',v_mit=1 and v_codes>0),
    'payer_registry',jsonb_build_object('schemes',v_schemes,'options_2026',v_options,'open_total',v_open,'open_covered',v_open_covered,'restricted_total',v_restricted,'restricted_covered',v_restricted_covered,'staging_ready',v_open_covered=v_open,'production_ready',v_restricted_covered=v_restricted),
    'switching',jsonb_build_object('sandbox_capabilities',v_sandbox_caps,'sandbox_connections',v_sandbox_connections,'sandbox_ready',v_sandbox_caps>0 and v_sandbox_connections>0,'external_production_capabilities',v_prod_caps,'production_connections',v_prod_connections,'production_ready',v_prod_caps>0 and v_prod_connections>0),
    'sources',jsonb_build_object('pending_review',v_pending_sources,'ready',v_pending_sources=0),
    'external_requirements',jsonb_build_object('waiting_external',v_waiting,'ready',v_waiting=0),
    'security',jsonb_build_object('sensitive_rls_enabled',v_rls,'private_storage_buckets',v_buckets,'unsafe_health_assist_policies',v_unsafe,'ready',v_rls and v_buckets and v_unsafe=0),
    'latest_automated_probe',v_latest_probe,
    'latest_validation_run',v_latest_run,
    'blockers',v_blockers
  );
end;
$$;

revoke all on function public.get_practicectrl_release_readiness(uuid) from public,anon;
grant execute on function public.get_practicectrl_release_readiness(uuid) to authenticated;

