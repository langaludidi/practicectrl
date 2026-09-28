
alter table public.practice_bootstrap_control
  add column if not exists failed_attempts integer not null default 0,
  add column if not exists last_failed_at timestamptz,
  add column if not exists locked_until timestamptz;

alter table public.practice_bootstrap_control
  drop constraint if exists practice_bootstrap_failed_attempts_ck;

alter table public.practice_bootstrap_control
  add constraint practice_bootstrap_failed_attempts_ck check (failed_attempts >= 0);

create or replace function public.register_bootstrap_token_attempt(
  p_practice_id uuid,
  p_success boolean
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_row public.practice_bootstrap_control%rowtype;
  v_now timestamptz := now();
  v_attempts integer;
  v_locked_until timestamptz;
begin
  select * into v_row
  from public.practice_bootstrap_control
  where practice_id=p_practice_id
  for update;

  if not found then
    return jsonb_build_object('configured',false,'locked',false,'failed_attempts',0);
  end if;

  if p_success then
    update public.practice_bootstrap_control
    set failed_attempts=0,last_failed_at=null,locked_until=null
    where practice_id=p_practice_id;

    return jsonb_build_object('configured',true,'locked',false,'failed_attempts',0);
  end if;

  if v_row.locked_until is not null and v_row.locked_until > v_now then
    return jsonb_build_object(
      'configured',true,
      'locked',true,
      'failed_attempts',v_row.failed_attempts,
      'locked_until',v_row.locked_until
    );
  end if;

  if v_row.last_failed_at is null or v_row.last_failed_at < v_now - interval '15 minutes' then
    v_attempts := 1;
  else
    v_attempts := v_row.failed_attempts + 1;
  end if;

  if v_attempts >= 5 then
    v_locked_until := v_now + interval '15 minutes';
  else
    v_locked_until := null;
  end if;

  update public.practice_bootstrap_control
  set failed_attempts=v_attempts,
      last_failed_at=v_now,
      locked_until=v_locked_until
  where practice_id=p_practice_id;

  return jsonb_build_object(
    'configured',true,
    'locked',v_locked_until is not null,
    'failed_attempts',v_attempts,
    'locked_until',v_locked_until
  );
end;
$$;

revoke all on function public.register_bootstrap_token_attempt(uuid,boolean) from public, anon, authenticated;
grant execute on function public.register_bootstrap_token_attempt(uuid,boolean) to service_role;

create or replace function public.accept_practice_staff_invitation_v2(
  p_invitation_id uuid,
  p_user_id uuid,
  p_email text
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_invite public.practice_staff_invitation%rowtype;
  v_now timestamptz := now();
begin
  select * into v_invite
  from public.practice_staff_invitation
  where id=p_invitation_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'code','not_found','message','Invitation not found');
  end if;

  if v_invite.status <> 'pending' then
    return jsonb_build_object('ok',false,'code','not_active','message','Invitation is not active');
  end if;

  if v_invite.expires_at <= v_now then
    update public.practice_staff_invitation
    set status='expired'
    where id=p_invitation_id and status='pending';

    insert into public.practice_access_event(
      practice_id,event_type,actor_user_id,subject_user_id,invitation_id
    ) values (
      v_invite.practice_id,'invite_expired',p_user_id,p_user_id,p_invitation_id
    );

    return jsonb_build_object('ok',false,'code','expired','message','Invitation has expired');
  end if;

  if lower(trim(p_email)) <> v_invite.email_normalized then
    return jsonb_build_object('ok',false,'code','email_mismatch','message','Invitation email mismatch');
  end if;

  if v_invite.invited_user_id is not null and v_invite.invited_user_id <> p_user_id then
    return jsonb_build_object('ok',false,'code','identity_mismatch','message','Invitation identity mismatch');
  end if;

  insert into public.practice_staff_member(practice_id,user_id,role,active,email)
  values(v_invite.practice_id,p_user_id,v_invite.role,true,lower(trim(p_email)))
  on conflict(practice_id,user_id) do update
    set role=excluded.role,active=true,email=excluded.email;

  update public.practice_staff_invitation
  set status='accepted',
      accepted_at=v_now,
      invited_user_id=p_user_id
  where id=p_invitation_id;

  if v_invite.invitation_kind='bootstrap_admin' then
    update public.practice_bootstrap_control
    set consumed_at=v_now,
        failed_attempts=0,
        last_failed_at=null,
        locked_until=null
    where practice_id=v_invite.practice_id
      and consumed_at is null;
  end if;

  insert into public.practice_access_event(
    practice_id,event_type,actor_user_id,subject_user_id,invitation_id,metadata
  ) values (
    v_invite.practice_id,'invite_accepted',p_user_id,p_user_id,p_invitation_id,
    jsonb_build_object('role',v_invite.role,'invitation_kind',v_invite.invitation_kind)
  );

  return jsonb_build_object('ok',true,'role',v_invite.role::text);
end;
$$;

revoke all on function public.accept_practice_staff_invitation_v2(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.accept_practice_staff_invitation_v2(uuid,uuid,text) to service_role;

