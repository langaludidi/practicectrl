
do $$
begin
  if to_regclass('public.pathology_test_concept') is null
     or to_regclass('public.pathology_provider_test_mapping') is null
     or to_regclass('public.pathology_specimen') is null
     or to_regclass('public.pathology_result_release') is null
     or to_regclass('public.pathology_safety_case') is null
     or to_regclass('public.pathology_follow_up_action') is null
  then
    raise exception 'PracticeCtrl v0.30.1 pathology intelligence tables are incomplete';
  end if;

  if to_regprocedure('public.record_corrected_pathology_result(uuid,text,text,timestamptz,text,text,jsonb)') is null
     or to_regprocedure('public.create_pathology_specimen(uuid,text,text,text)') is null
     or to_regprocedure('public.update_pathology_specimen_status(uuid,text,text,timestamptz)') is null
     or to_regprocedure('public.approve_pathology_result_for_patient(uuid)') is null
     or to_regprocedure('public.create_pathology_follow_up_action(uuid,text,timestamptz,text)') is null
     or to_regprocedure('public.file_pathology_result_inbox(uuid,text,timestamptz,text,jsonb)') is null
     or to_regprocedure('public.get_pathology_trend_series(uuid,uuid,uuid,text,integer)') is null
  then
    raise exception 'PracticeCtrl v0.30.1 pathology intelligence RPCs are incomplete';
  end if;

  if not exists(
    select 1 from cron.job
    where jobname='practicectrl-pathology-safety-10m'
      and active
      and command='select private.process_pathology_safety_escalations();'
  ) then
    raise exception 'PracticeCtrl v0.30.1 pathology safety scheduler is not active';
  end if;
end $$;

