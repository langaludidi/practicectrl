
create index if not exists medicines_ai_review_capability_idx
  on public.medicines_ai_review(capability_key);
do $$
begin
  if to_regclass('public.medicines_ai_review') is null
     or to_regclass('public.medicines_ai_source_file') is null
     or to_regclass('public.medicines_ai_review_source') is null
  then raise exception 'PracticeCtrl v0.31 medicines AI governance tables are incomplete'; end if;

  if to_regprocedure('public.get_medicines_ai_readiness(uuid,text)') is null
     or to_regprocedure('public.review_medicines_ai_output(uuid,text)') is null
     or to_regprocedure('public.apply_medicines_ai_review(uuid)') is null
  then raise exception 'PracticeCtrl v0.31 medicines AI governance RPCs are incomplete'; end if;

  if not exists(select 1 from storage.buckets where id='medicines-ai-files' and public=false) then
    raise exception 'PracticeCtrl v0.31 medicines AI source storage is not private';
  end if;

  if exists(
    select 1 from public.practice_assist_policy p
    where p.capability_key like 'medicines.%' and p.enabled
      and (
        p.allowed_data_class<>'health_special'
        or p.retain_raw_input
        or p.retain_raw_output
        or not p.require_aal2
        or not p.human_review_required
      )
  ) then raise exception 'Unsafe enabled medicines AI policy detected'; end if;
end $$;
