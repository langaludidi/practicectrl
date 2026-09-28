
create or replace function public.get_practicectrl_readiness(p_practice_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,storage,pg_temp
as $$
declare
  v_staff integer;
  v_origin boolean;
  v_mit integer;
  v_codes bigint;
  v_schemes bigint;
  v_options bigint;
  v_external_prod bigint;
  v_prod_connections bigint;
  v_waiting bigint;
  v_pending_sources bigint;
  v_private_buckets boolean;
  v_rls boolean;
  v_unsafe_assist bigint;
begin
  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=p_practice_id
      and m.active
      and m.role in ('practice_manager','system_admin','auditor')
  ) then raise exception 'Privileged PracticeCtrl role required'; end if;

  select count(*) into v_staff from public.practice_staff_member where practice_id=p_practice_id and active;
  select exists(select 1 from public.practice_app_origin where practice_id=p_practice_id and environment='staging' and active) into v_origin;
  select count(*) into v_mit from public.coding_source_release where authority='NDOH' and source_name='ICD-10 Master Industry Table' and status='active';
  select count(*) into v_codes from public.sa_icd10_code c join public.coding_source_release r on r.id=c.source_release_id where r.status='active' and r.authority='NDOH';
  select count(*) into v_schemes from public.medical_scheme;
  select count(*) into v_options from public.medical_scheme_option;
  select count(*) into v_external_prod
    from public.integration_adapter_capability a
    join public.integration_provider p on p.id=a.provider_id
    where a.executable_production and p.slug<>'practicectrl-sandbox';
  select count(*) into v_prod_connections
    from public.practice_integration_connection
    where practice_id=p_practice_id and environment='production' and status in ('production_ready','active');
  select count(*) into v_waiting
    from public.integration_requirement where status='waiting_external';
  select count(*) into v_pending_sources
    from public.source_dataset_release where status='pending_review';

  select coalesce(bool_and(public=false),true) into v_private_buckets
  from storage.buckets where id in ('switch-payloads','governed-source-files','practice-import-files');

  select coalesce(bool_and(c.relrowsecurity),false) into v_rls
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname in (
    'crm_patient','crm_contact_point','crm_patient_scheme_membership',
    'billing_invoice','billing_payment_receipt','claim_record','remittance_advice',
    'revenue_account_snapshot','communication_thread','operations_work_item',
    'practice_staff_invitation','assist_interaction','payer_transaction'
  );

  select count(*) into v_unsafe_assist
  from public.practice_assist_policy
  where practice_id=p_practice_id
    and enabled
    and allowed_data_class='health_special'
    and (retain_raw_input or retain_raw_output);

  return jsonb_build_object(
    'generated_at',now(),
    'staff',jsonb_build_object('active_count',v_staff,'ready',v_staff>0),
    'deployment',jsonb_build_object('staging_origin_configured',v_origin,'ready',v_origin),
    'code10',jsonb_build_object('active_ndoh_mit_releases',v_mit,'active_codes',v_codes,'ready',v_mit=1 and v_codes>0),
    'payer_registry',jsonb_build_object('schemes',v_schemes,'options',v_options,'ready',v_schemes>0 and v_options>0),
    'switching',jsonb_build_object('external_production_capabilities',v_external_prod,'production_connections',v_prod_connections,'ready',v_external_prod>0 and v_prod_connections>0),
    'external_requirements',jsonb_build_object('waiting_external',v_waiting,'ready',v_waiting=0),
    'sources',jsonb_build_object('pending_review',v_pending_sources,'ready',v_pending_sources=0),
    'security',jsonb_build_object(
      'sensitive_rls_enabled',v_rls,
      'private_storage_buckets',v_private_buckets,
      'unsafe_health_assist_policies',v_unsafe_assist,
      'ready',v_rls and v_private_buckets and v_unsafe_assist=0
    ),
    'production_ready',
      (v_staff>0 and v_origin and v_mit=1 and v_codes>0 and
       v_schemes>0 and v_options>0 and v_external_prod>0 and v_prod_connections>0 and
       v_waiting=0 and v_pending_sources=0 and v_rls and v_private_buckets and v_unsafe_assist=0)
  );
end;
$$;

revoke all on function public.get_practicectrl_readiness(uuid) from public,anon;
grant execute on function public.get_practicectrl_readiness(uuid) to authenticated;

