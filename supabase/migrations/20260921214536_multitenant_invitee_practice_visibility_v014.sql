
drop policy if exists practice_pending_invitee_read on public.practice;
create policy practice_pending_invitee_read on public.practice
for select to authenticated
using (
  exists (
    select 1
    from public.practice_staff_invitation i
    where i.practice_id=practice.id
      and i.status='pending'
      and i.expires_at>now()
      and lower(i.email_normalized)=lower(coalesce((select auth.jwt())->>'email',''))
  )
);

