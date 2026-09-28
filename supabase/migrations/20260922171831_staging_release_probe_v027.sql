
create table if not exists public.release_probe_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  run_id uuid references public.release_validation_run(id) on delete set null,
  release_version text not null,
  probe_version text not null,
  checks jsonb not null default '[]'::jsonb,
  passed_count integer not null default 0 check (passed_count >= 0),
  failed_count integer not null default 0 check (failed_count >= 0),
  all_passed boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists release_probe_snapshot_practice_created_idx on public.release_probe_snapshot(practice_id,created_at desc);
create index if not exists release_probe_snapshot_run_idx on public.release_probe_snapshot(run_id) where run_id is not null;
create index if not exists release_probe_snapshot_created_by_idx on public.release_probe_snapshot(created_by);
alter table public.release_probe_snapshot enable row level security;
revoke all on table public.release_probe_snapshot from anon, authenticated;
grant select on table public.release_probe_snapshot to authenticated;
create policy release_probe_snapshot_read on public.release_probe_snapshot
for select to authenticated
using (
 exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=release_probe_snapshot.practice_id and m.active and m.role in ('practice_manager','system_admin','auditor'))
 or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active)
);

create or replace function public.get_release_automated_checks(p_practice_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,storage,pg_temp
as $$
declare
 v_user uuid := (select auth.uid());
 v_staff integer;
 v_origin boolean;
 v_private_buckets boolean;
 v_rls boolean;
 v_open bigint;
 v_open_covered bigint;
 v_sandbox_caps bigint;
 v_sandbox_conn bigint;
 v_mit integer;
 v_codes bigint;
 v_checks jsonb := '[]'::jsonb;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 if ((select auth.jwt())->>'aal') is distinct from 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
 if not (
   exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=p_practice_id and m.active and m.role in ('practice_manager','system_admin','auditor'))
   or exists(select 1 from public.platform_operator po where po.user_id=v_user and po.active)
 ) then raise exception 'Privileged PracticeCtrl role required'; end if;

 select count(*) into v_staff from public.practice_staff_member where practice_id=p_practice_id and active;
 select exists(select 1 from public.practice_app_origin where practice_id=p_practice_id and environment='staging' and active) into v_origin;
 select (count(*)=5 and coalesce(bool_and(public=false),false)) into v_private_buckets
 from storage.buckets where id in ('switch-payloads','governed-source-files','practice-import-files','patient-intake-files','payer-contract-files');
 select coalesce(bool_and(c.relrowsecurity),false) into v_rls
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname in ('crm_patient','clinical_note','billing_invoice','claim_record','remittance_advice','release_validation_run','release_validation_step','release_probe_snapshot');
 select count(*) into v_open from public.medical_scheme where scheme_type='open';
 select count(distinct o.medical_scheme_id) into v_open_covered
 from public.medical_scheme_option o join public.medical_scheme m on m.id=o.medical_scheme_id
 where o.benefit_year=2026 and o.approval_status='approved' and m.scheme_type='open';
 select count(*) into v_sandbox_caps
 from public.integration_adapter_capability a join public.integration_provider p on p.id=a.provider_id
 where a.executable_sandbox and p.slug='practicectrl-sandbox';
 select count(*) into v_sandbox_conn
 from public.practice_integration_connection c join public.integration_provider p on p.id=c.provider_id
 where c.practice_id=p_practice_id and c.environment='sandbox' and c.status in ('sandbox_active','active','production_ready') and p.slug='practicectrl-sandbox';
 select count(*) into v_mit from public.coding_source_release where authority='NDOH' and source_name='ICD-10 Master Industry Table' and status='active';
 select count(*) into v_codes from public.sa_icd10_code c join public.coding_source_release r on r.id=c.source_release_id where r.status='active' and r.authority='NDOH';

 v_checks := v_checks || jsonb_build_array(jsonb_build_object('key','tenant_staff','label','Active tenant staff','passed',v_staff>0,'detail',v_staff||' active staff'));
 v_checks := v_checks || jsonb_build_array(jsonb_build_object('key','staging_origin','label','Dedicated staging origin','passed',v_origin,'detail',case when v_origin then 'Configured' else 'Not configured' end));
 v_checks := v_checks || jsonb_build_array(jsonb_build_object('key','private_storage','label','Private sensitive storage','passed',v_private_buckets,'detail','Required clinical/revenue buckets must remain private'));
 v_checks := v_checks || jsonb_build_array(jsonb_build_object('key','rls','label','Sensitive table RLS','passed',v_rls,'detail','Core clinical/revenue/release tables'));
 v_checks := v_checks || jsonb_build_array(jsonb_build_object('key','open_scheme_master','label','2026 open-scheme option coverage','passed',v_open>0 and v_open_covered=v_open,'detail',v_open_covered||'/'||v_open||' open schemes'));
 v_checks := v_checks || jsonb_build_array(jsonb_build_object('key','sandbox_gateway','label','Sandbox payer gateway','passed',v_sandbox_caps>0 and v_sandbox_conn>0,'detail',v_sandbox_caps||' capabilities · '||v_sandbox_conn||' connection'));
 v_checks := v_checks || jsonb_build_array(jsonb_build_object('key','code10_authority','label','Code10 governed NDoH MIT','passed',v_mit=1 and v_codes>0,'detail',v_codes||' active authority codes'));

 return jsonb_build_object(
   'probe_version','pc-staging-probe-v1',
   'release_target','0.27.0-dev.1',
   'checks',v_checks,
   'passed_count',(select count(*) from jsonb_array_elements(v_checks) x where (x->>'passed')::boolean),
   'failed_count',(select count(*) from jsonb_array_elements(v_checks) x where not (x->>'passed')::boolean),
   'all_passed',not exists(select 1 from jsonb_array_elements(v_checks) x where not (x->>'passed')::boolean)
 );
end $$;
revoke all on function public.get_release_automated_checks(uuid) from public,anon;
grant execute on function public.get_release_automated_checks(uuid) to authenticated;

