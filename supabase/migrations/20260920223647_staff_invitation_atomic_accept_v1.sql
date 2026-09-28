begin;

create or replace function public.accept_practice_staff_invitation(
  p_invitation_id uuid,
  p_user_id uuid,
  p_email text
)
returns public.practice_staff_role
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_invite public.practice_staff_invitation%rowtype;
  v_now timestamptz := now();
begin
  select * into v_invite
  from public.practice_staff_invitation
  where id=p_invitation_id
  for update;

  if not found then raise exception 'Invitation not found'; end if;
  if v_invite.status <> 'pending' then raise exception 'Invitation is not active'; end if;

  if v_invite.expires_at <= v_now then
    update public.practice_staff_invitation
    set status='expired'
    where id=p_invitation_id;
    insert into public.practice_access_event(
      practice_id,event_type,actor_user_id,subject_user_id,invitation_id
    ) values (
      v_invite.practice_id,'invite_expired',p_user_id,p_user_id,p_invitation_id
    );
    raise exception 'Invitation has expired';
  end if;

  if lower(trim(p_email)) <> v_invite.email_normalized then
    raise exception 'Invitation email mismatch';
  end if;

  if v_invite.invited_user_id is not null and v_invite.invited_user_id <> p_user_id then
    raise exception 'Invitation identity mismatch';
  end if;

  insert into public.practice_staff_member(practice_id,user_id,role,active)
  values(v_invite.practice_id,p_user_id,v_invite.role,true)
  on conflict(practice_id,user_id) do update
    set role=excluded.role, active=true;

  update public.practice_staff_invitation
  set status='accepted',
      accepted_at=v_now,
      invited_user_id=p_user_id
  where id=p_invitation_id;

  insert into public.practice_access_event(
    practice_id,event_type,actor_user_id,subject_user_id,invitation_id,metadata
  ) values (
    v_invite.practice_id,'invite_accepted',p_user_id,p_user_id,p_invitation_id,
    jsonb_build_object('role',v_invite.role,'invitation_kind',v_invite.invitation_kind)
  );

  return v_invite.role;
end;
$$;

revoke all on function public.accept_practice_staff_invitation(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.accept_practice_staff_invitation(uuid,uuid,text)
  to service_role;

commit;
