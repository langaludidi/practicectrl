create index if not exists platform_operator_created_by_idx on public.platform_operator(created_by) where created_by is not null;
create index if not exists platform_tenant_event_actor_user_idx on public.platform_tenant_event(actor_user_id) where actor_user_id is not null;
create index if not exists platform_tenant_event_practice_idx on public.platform_tenant_event(practice_id) where practice_id is not null;
create index if not exists user_practice_preference_practice_idx on public.user_practice_preference(last_practice_id);

drop policy if exists practice_member_read_practice on public.practice;
drop policy if exists practice_pending_invitee_read on public.practice;
drop policy if exists practice_platform_operator_read on public.practice;
drop policy if exists practice_authorized_read on public.practice;
create policy practice_authorized_read on public.practice
for select to authenticated
using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice.id and m.active)
  or exists(select 1 from public.practice_staff_invitation i where i.practice_id=practice.id and i.status='pending' and i.expires_at>now() and lower(i.email_normalized)=lower(coalesce((select auth.jwt())->>'email','')))
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active)
);

drop policy if exists source_dataset_staff_read on public.source_dataset;
drop policy if exists source_dataset_platform_operator_read on public.source_dataset;
drop policy if exists source_dataset_authorized_read on public.source_dataset;
create policy source_dataset_authorized_read on public.source_dataset
for select to authenticated
using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active)
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active)
);

drop policy if exists source_dataset_release_staff_read on public.source_dataset_release;
drop policy if exists source_dataset_release_platform_operator_read on public.source_dataset_release;
drop policy if exists source_dataset_release_authorized_read on public.source_dataset_release;
create policy source_dataset_release_authorized_read on public.source_dataset_release
for select to authenticated
using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active)
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active)
);

drop policy if exists coding_sources_member_read on public.coding_source_release;
drop policy if exists coding_source_release_platform_operator_read on public.coding_source_release;
drop policy if exists coding_source_release_authorized_read on public.coding_source_release;
create policy coding_source_release_authorized_read on public.coding_source_release
for select to authenticated
using (
  exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.active)
  or exists(select 1 from public.platform_operator po where po.user_id=(select auth.uid()) and po.active)
);
