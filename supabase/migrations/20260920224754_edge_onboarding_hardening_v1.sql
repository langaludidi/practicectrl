begin;
drop policy if exists practice_app_origin_deny_client on public.practice_app_origin;
create policy practice_app_origin_deny_client
on public.practice_app_origin for all to anon,authenticated
using(false) with check(false);

drop policy if exists practice_bootstrap_control_deny_client on public.practice_bootstrap_control;
create policy practice_bootstrap_control_deny_client
on public.practice_bootstrap_control for all to anon,authenticated
using(false) with check(false);
commit;
