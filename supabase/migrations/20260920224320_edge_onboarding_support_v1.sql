
begin;

alter table public.practice_staff_member
  add column if not exists email text;

create unique index if not exists practice_staff_member_email_uq
  on public.practice_staff_member(practice_id, lower(email))
  where email is not null;

drop policy if exists practice_staff_privileged_read on public.practice_staff_member;
create policy practice_staff_privileged_read
on public.practice_staff_member for select to authenticated
using (
  exists (
    select 1 from public.practice_staff_member me
    where me.user_id=(select auth.uid())
      and me.practice_id=practice_staff_member.practice_id
      and me.active
      and me.role in ('practice_manager','system_admin','auditor')
  )
);

create table if not exists public.practice_app_origin (
  practice_id uuid not null references public.practice(id) on delete cascade,
  environment text not null check (environment in ('staging','production')),
  origin text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(practice_id,environment),
  constraint practice_app_origin_https_ck check (
    origin ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$'
  )
);

create table if not exists public.practice_bootstrap_control (
  practice_id uuid primary key references public.practice(id) on delete cascade,
  token_sha256 text not null check (token_sha256 ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint practice_bootstrap_expiry_ck check (expires_at > created_at)
);

alter table public.practice_app_origin enable row level security;
alter table public.practice_bootstrap_control enable row level security;
revoke all on table public.practice_app_origin from anon,authenticated;
revoke all on table public.practice_bootstrap_control from anon,authenticated;

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

  insert into public.practice_staff_member(practice_id,user_id,role,active,email)
  values(v_invite.practice_id,p_user_id,v_invite.role,true,lower(trim(p_email)))
  on conflict(practice_id,user_id) do update
    set role=excluded.role, active=true, email=excluded.email;

  update public.practice_staff_invitation
  set status='accepted',
      accepted_at=v_now,
      invited_user_id=p_user_id
  where id=p_invitation_id;

  if v_invite.invitation_kind='bootstrap_admin' then
    update public.practice_bootstrap_control
    set consumed_at=v_now
    where practice_id=v_invite.practice_id
      and consumed_at is null;
  end if;

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
