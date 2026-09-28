
drop policy if exists intake_staff_manage on public.patient_intake_session;
create policy intake_staff_insert on public.patient_intake_session for insert to authenticated
with check(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_session.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));
create policy intake_staff_update on public.patient_intake_session for update to authenticated
using(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_session.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')))
with check(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_session.practice_id and m.active and m.role in('reception','practice_manager','clinical_admin','system_admin')));
create policy intake_staff_delete on public.patient_intake_session for delete to authenticated
using(((select auth.jwt())->>'aal')='aal2' and exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=patient_intake_session.practice_id and m.active and m.role in('practice_manager','system_admin')));

