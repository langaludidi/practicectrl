
do $$
begin
  if to_regclass('public.pathology_ai_review') is null then
    raise exception 'PracticeCtrl v0.30.1 pathology AI review table is missing';
  end if;

  if to_regprocedure('public.get_pathology_ai_readiness(uuid)') is null
     or to_regprocedure('public.review_pathology_ai_summary(uuid,text)') is null
  then
    raise exception 'PracticeCtrl v0.30.1 pathology AI governance RPCs are incomplete';
  end if;

  if not exists(
    select 1 from pg_indexes
    where schemaname='public'
      and tablename='pathology_ai_review'
      and indexname='pathology_ai_review_capability_key_idx'
  ) then
    raise exception 'PracticeCtrl v0.30.1 pathology AI capability index is missing';
  end if;

  if exists(
    select 1 from public.practice_assist_policy p
    where p.capability_key='pathology.result_intelligence'
      and p.enabled
      and (
        p.allowed_data_class<>'health_special'
        or p.retain_raw_input
        or p.retain_raw_output
        or not p.require_aal2
        or not p.human_review_required
      )
  ) then
    raise exception 'Unsafe enabled pathology AI policy detected';
  end if;
end $$;

