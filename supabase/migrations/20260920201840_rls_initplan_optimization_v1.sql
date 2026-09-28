
begin;

-- Rewrite AAL checks so auth.jwt() is evaluated once per statement (init plan).

drop policy if exists coding_session_mfa_insert on public.coding_session;
create policy coding_session_mfa_insert
on public.coding_session as restrictive for insert to authenticated
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_session_mfa_update on public.coding_session;
create policy coding_session_mfa_update
on public.coding_session as restrictive for update to authenticated
using (((select auth.jwt())->>'aal') = 'aal2')
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_candidate_mfa_insert on public.coding_candidate_snapshot;
create policy coding_candidate_mfa_insert
on public.coding_candidate_snapshot as restrictive for insert to authenticated
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_decision_mfa_insert on public.coding_decision;
create policy coding_decision_mfa_insert
on public.coding_decision as restrictive for insert to authenticated
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_confidentiality_mfa_insert on public.coding_confidentiality_event;
create policy coding_confidentiality_mfa_insert
on public.coding_confidentiality_event as restrictive for insert to authenticated
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_validation_mfa_insert on public.coding_validation_event;
create policy coding_validation_mfa_insert
on public.coding_validation_event as restrictive for insert to authenticated
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_validation_mfa_update on public.coding_validation_event;
create policy coding_validation_mfa_update
on public.coding_validation_event as restrictive for update to authenticated
using (((select auth.jwt())->>'aal') = 'aal2')
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists pmb_review_mfa_insert on public.pmb_review;
create policy pmb_review_mfa_insert
on public.pmb_review as restrictive for insert to authenticated
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists pmb_review_mfa_update on public.pmb_review;
create policy pmb_review_mfa_update
on public.pmb_review as restrictive for update to authenticated
using (((select auth.jwt())->>'aal') = 'aal2')
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_ai_mfa_insert on public.coding_ai_interaction;
create policy coding_ai_mfa_insert
on public.coding_ai_interaction as restrictive for insert to authenticated
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_ai_mfa_update on public.coding_ai_interaction;
create policy coding_ai_mfa_update
on public.coding_ai_interaction as restrictive for update to authenticated
using (((select auth.jwt())->>'aal') = 'aal2')
with check (((select auth.jwt())->>'aal') = 'aal2');

drop policy if exists coding_source_file_admin_select on public.coding_source_file;
create policy coding_source_file_admin_select
on public.coding_source_file for select to authenticated
using (
  ((select auth.jwt())->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

drop policy if exists coding_source_file_admin_insert on public.coding_source_file;
create policy coding_source_file_admin_insert
on public.coding_source_file for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and bucket_id = 'coding-source-files'
  and ((select auth.jwt())->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

drop policy if exists coding_source_file_admin_update on public.coding_source_file;
create policy coding_source_file_admin_update
on public.coding_source_file for update to authenticated
using (
  ((select auth.jwt())->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
)
with check (
  bucket_id = 'coding-source-files'
  and ((select auth.jwt())->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

drop policy if exists coding_source_files_admin_select on storage.objects;
create policy coding_source_files_admin_select
on storage.objects for select to authenticated
using (
  bucket_id = 'coding-source-files'
  and ((select auth.jwt())->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

drop policy if exists coding_source_files_admin_insert on storage.objects;
create policy coding_source_files_admin_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'coding-source-files'
  and ((select auth.jwt())->>'aal') = 'aal2'
  and exists (
    select 1 from public.practice_staff_member m
    where m.user_id = (select auth.uid())
      and m.active = true
      and m.role = 'system_admin'
  )
);

commit;
