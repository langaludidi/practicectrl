do $$
begin
  if to_regclass('public.communication_automation_rule') is null
     or to_regclass('public.communication_automation_job') is null
     or to_regclass('public.communication_automation_event') is null
     or to_regprocedure('private.process_communication_automation(uuid)') is null
     or to_regprocedure('public.get_communication_readiness(uuid)') is null
     or to_regprocedure('public.set_patient_communication_preferences(uuid,uuid,text,boolean,boolean,boolean,boolean,boolean)') is null
     or to_regprocedure('public.record_communication_preference(uuid,uuid,text,text,text,text)') is null
  then
    raise exception 'PracticeCtrl v0.29 communications automation objects are incomplete';
  end if;

  if not exists(
    select 1 from cron.job
    where jobname='practicectrl-communication-automation-5m'
      and active
      and command='select private.process_communication_automation(null);'
  ) then
    raise exception 'PracticeCtrl v0.29 communications scheduler is not active';
  end if;
end $$;
