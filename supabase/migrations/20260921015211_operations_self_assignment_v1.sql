
create or replace function public.claim_operations_work_item(p_work_item_id uuid)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_item public.operations_work_item%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_item from public.operations_work_item where id=p_work_item_id for update;
  if not found then raise exception 'Work item not found or not accessible'; end if;
  if v_item.status in ('completed','cancelled') then raise exception 'Closed work item cannot be claimed'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_item.practice_id and m.active and m.role<>'auditor'
  ) then raise exception 'Active operations role required'; end if;

  update public.operations_work_item
  set owner_user_id=v_user,
      status=case when status='open' then 'in_progress' else status end,
      updated_at=now()
  where id=p_work_item_id;

  insert into public.operations_work_event(work_item_id,event_type,actor_user_id,metadata)
  values(
    p_work_item_id,'assigned',v_user,
    jsonb_build_object('previous_owner',v_item.owner_user_id,'new_owner',v_user,'self_claim',true)
  );

  return p_work_item_id;
end;
$$;
revoke all on function public.claim_operations_work_item(uuid) from public,anon;
grant execute on function public.claim_operations_work_item(uuid) to authenticated;
