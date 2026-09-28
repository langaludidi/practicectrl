
do $$
begin
  if to_regclass('public.pathology_order') is null
     or to_regclass('public.pathology_order_item') is null
     or to_regclass('public.pathology_result') is null
     or to_regclass('public.pathology_result_item') is null
     or to_regclass('public.pathology_result_acknowledgement') is null
     or to_regclass('public.pathology_result_document') is null
     or to_regclass('public.pathology_audit_event') is null
  then
    raise exception 'PracticeCtrl v0.30 pathology tables are incomplete';
  end if;

  if to_regprocedure('public.create_pathology_order(uuid,uuid,uuid,uuid,text,text,boolean,text,jsonb)') is null
     or to_regprocedure('public.submit_pathology_order(uuid,text,text)') is null
     or to_regprocedure('public.record_pathology_result(uuid,text,text,text,text,timestamptz,timestamptz,text,jsonb)') is null
     or to_regprocedure('public.acknowledge_pathology_result(uuid,text,text,timestamptz)') is null
     or to_regprocedure('public.get_pathology_readiness(uuid)') is null
     or to_regprocedure('public.get_pathology_metrics(uuid,integer)') is null
  then
    raise exception 'PracticeCtrl v0.30 pathology RPCs are incomplete';
  end if;

  if not exists(select 1 from storage.buckets where id='pathology-result-files' and public=false) then
    raise exception 'PracticeCtrl v0.30 pathology result storage is not private';
  end if;

  if not exists(
    select 1
    from public.integration_provider p
    join public.integration_adapter_capability ac on ac.provider_id=p.id
    where p.slug='practicectrl-pathology-sandbox'
      and ac.capability_code='pathology_order_submit'
      and ac.executable_sandbox
      and not ac.executable_production
  ) then
    raise exception 'PracticeCtrl v0.30 pathology sandbox order capability is not correctly gated';
  end if;
end $$;

