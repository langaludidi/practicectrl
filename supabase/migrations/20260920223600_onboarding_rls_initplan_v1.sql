begin;
drop policy if exists practice_staff_invitation_privileged_read on public.practice_staff_invitation;
create policy practice_staff_invitation_privileged_read
on public.practice_staff_invitation for select to authenticated
using (
  invited_user_id=(select auth.uid())
  or lower(email_normalized)=lower(coalesce(((select auth.jwt())->>'email'),''))
  or exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=practice_staff_invitation.practice_id
      and m.active
      and m.role in ('practice_manager','system_admin','auditor')
  )
);
commit;
