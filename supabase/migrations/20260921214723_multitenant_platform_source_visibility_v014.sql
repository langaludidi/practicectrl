
drop policy if exists source_dataset_platform_operator_read on public.source_dataset;
create policy source_dataset_platform_operator_read on public.source_dataset
for select to authenticated
using (exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active));

drop policy if exists source_dataset_release_platform_operator_read on public.source_dataset_release;
create policy source_dataset_release_platform_operator_read on public.source_dataset_release
for select to authenticated
using (exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active));

drop policy if exists coding_source_release_platform_operator_read on public.coding_source_release;
create policy coding_source_release_platform_operator_read on public.coding_source_release
for select to authenticated
using (exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active));

