
do $$
begin
  if not exists (
    select 1 from pg_enum
    where enumtypid='public.integration_provider_type'::regtype
      and enumlabel='pathology_lab'
  ) then
    raise exception 'PracticeCtrl v0.30 pathology_lab provider type is missing';
  end if;
end $$;

