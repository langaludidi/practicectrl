
begin;

drop policy if exists coding_source_files_admin_select on storage.objects;
create policy coding_source_files_admin_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'coding-source-files'
  and (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1
    from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

drop policy if exists coding_source_files_admin_insert on storage.objects;
create policy coding_source_files_admin_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'coding-source-files'
  and (select auth.jwt()->>'aal') = 'aal2'
  and exists (
    select 1
    from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

commit;
