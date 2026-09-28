
begin;

drop policy if exists source_import_batch_deny_client on public.source_import_batch;
create policy source_import_batch_deny_client
on public.source_import_batch for all
to anon,authenticated
using(false) with check(false);

drop policy if exists medical_scheme_import_staging_deny_client on public.medical_scheme_import_staging;
create policy medical_scheme_import_staging_deny_client
on public.medical_scheme_import_staging for all
to anon,authenticated
using(false) with check(false);

drop policy if exists medical_scheme_option_import_staging_deny_client on public.medical_scheme_option_import_staging;
create policy medical_scheme_option_import_staging_deny_client
on public.medical_scheme_option_import_staging for all
to anon,authenticated
using(false) with check(false);

create index if not exists source_import_batch_created_by_idx
  on public.source_import_batch(created_by) where created_by is not null;
create index if not exists source_import_batch_reviewed_by_idx
  on public.source_import_batch(reviewed_by) where reviewed_by is not null;
create index if not exists source_import_batch_promoted_by_idx
  on public.source_import_batch(promoted_by) where promoted_by is not null;

commit;
