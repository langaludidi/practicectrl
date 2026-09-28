
begin;

create table if not exists public.practice_staff_invitation (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  email text not null,
  email_normalized text not null,
  role public.practice_staff_role not null,
  invited_user_id uuid references auth.users(id) on delete set null,
  invited_by uuid references auth.users(id) on delete set null,
  invitation_kind text not null default 'staff'
    check (invitation_kind in ('bootstrap_admin','staff')),
  status text not null default 'pending'
    check (status in ('pending','accepted','revoked','expired','send_failed')),
  expires_at timestamptz not null,
  sent_at timestamptz,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint practice_staff_invitation_email_ck
    check (email_normalized = lower(trim(email))),
  constraint practice_staff_invitation_bootstrap_role_ck
    check (invitation_kind <> 'bootstrap_admin' or role = 'system_admin'),
  constraint practice_staff_invitation_dates_ck
    check (
      (status <> 'accepted' or accepted_at is not null)
      and (status <> 'revoked' or revoked_at is not null)
    )
);

create unique index if not exists practice_staff_invitation_pending_email_uq
  on public.practice_staff_invitation(practice_id,email_normalized)
  where status='pending';

create unique index if not exists practice_staff_invitation_bootstrap_pending_uq
  on public.practice_staff_invitation(practice_id)
  where invitation_kind='bootstrap_admin' and status='pending';

create index if not exists practice_staff_invitation_user_idx
  on public.practice_staff_invitation(invited_user_id)
  where invited_user_id is not null;

create index if not exists practice_staff_invitation_invited_by_idx
  on public.practice_staff_invitation(invited_by)
  where invited_by is not null;

create index if not exists practice_staff_invitation_status_idx
  on public.practice_staff_invitation(practice_id,status,created_at desc);

create table if not exists public.practice_access_event (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  event_type text not null
    check (event_type in (
      'bootstrap_invite_sent','staff_invite_sent','invite_send_failed',
      'invite_accepted','invite_revoked','invite_expired',
      'staff_deactivated','staff_reactivated','role_changed'
    )),
  actor_user_id uuid references auth.users(id) on delete set null,
  subject_user_id uuid references auth.users(id) on delete set null,
  invitation_id uuid references public.practice_staff_invitation(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists practice_access_event_practice_idx
  on public.practice_access_event(practice_id,created_at desc);
create index if not exists practice_access_event_actor_idx
  on public.practice_access_event(actor_user_id)
  where actor_user_id is not null;
create index if not exists practice_access_event_subject_idx
  on public.practice_access_event(subject_user_id)
  where subject_user_id is not null;
create index if not exists practice_access_event_invitation_idx
  on public.practice_access_event(invitation_id)
  where invitation_id is not null;

alter table public.practice_staff_invitation enable row level security;
alter table public.practice_access_event enable row level security;

revoke all on table public.practice_staff_invitation from anon,authenticated;
revoke all on table public.practice_access_event from anon,authenticated;

grant select on table public.practice_staff_invitation to authenticated;
grant select on table public.practice_access_event to authenticated;

drop policy if exists practice_staff_invitation_privileged_read on public.practice_staff_invitation;
create policy practice_staff_invitation_privileged_read
on public.practice_staff_invitation for select to authenticated
using (
  invited_user_id=(select auth.uid())
  or lower(email_normalized)=lower(coalesce((select auth.jwt()->>'email'),''))
  or exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=practice_staff_invitation.practice_id
      and m.active
      and m.role in ('practice_manager','system_admin','auditor')
  )
);

drop policy if exists practice_access_event_privileged_read on public.practice_access_event;
create policy practice_access_event_privileged_read
on public.practice_access_event for select to authenticated
using (
  subject_user_id=(select auth.uid())
  or exists (
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=practice_access_event.practice_id
      and m.active
      and m.role in ('practice_manager','system_admin','auditor')
  )
);

-- No authenticated INSERT/UPDATE/DELETE grants or policies.
-- Invitation creation/acceptance is performed by trusted server routes using
-- the Supabase secret key after session/bootstrap validation.

commit;
