-- Dr Tembisa Tini Inc Practice CRM — canonical staff/RBAC foundation.
-- Integration SQL only. Generate the actual migration with Supabase CLI in the target project.
begin;

do $$ begin
  create type public.practice_staff_role as enum (
    'practitioner','reception','billing','practice_manager','clinical_admin','auditor','system_admin'
  );
exception when duplicate_object then null; end $$;

create table if not exists public.practice (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.practice_staff_member (
  practice_id uuid not null references public.practice(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.practice_staff_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (practice_id,user_id)
);
create index if not exists practice_staff_member_user_idx on public.practice_staff_member(user_id) where active;

alter table public.practice enable row level security;
alter table public.practice_staff_member enable row level security;

revoke all on table public.practice from anon, authenticated;
revoke all on table public.practice_staff_member from anon, authenticated;
grant select on table public.practice to authenticated;
grant select on table public.practice_staff_member to authenticated;

create policy practice_member_read_practice on public.practice for select to authenticated using (
  exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=practice.id and m.active)
);
create policy practice_staff_self_read on public.practice_staff_member for select to authenticated using (
  user_id=(select auth.uid()) and active
);

commit;
