
begin;

create unique index if not exists revenue_collection_case_snapshot_uq
  on public.revenue_collection_case(revenue_snapshot_id)
  where revenue_snapshot_id is not null;

create or replace function public.revenue_snapshot_guard_and_case()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
begin
  if new.account_ref is not null then
    update public.revenue_account_snapshot
    set source_freshness_status='superseded'
    where practice_id=new.practice_id
      and account_ref=new.account_ref
      and id<>new.id
      and source_freshness_status='current'
      and snapshot_at<=new.snapshot_at;
  end if;

  if new.total_amount > 0 then
    insert into public.revenue_collection_case(
      practice_id,patient_id,revenue_snapshot_id,account_ref,
      case_status,liability_status,balance_snapshot,suppress_automation,
      suppression_reason,notes,created_by
    )
    values(
      new.practice_id,new.patient_id,new.id,new.account_ref,
      'review_required',new.liability_status,new.total_amount,true,
      coalesce(new.suppression_reason,'Patient-versus-scheme liability requires review before contact'),
      'Created automatically from a VeriClaim ageing snapshot. No automated patient contact is permitted until liability is verified.',
      null
    )
    on conflict (revenue_snapshot_id) where revenue_snapshot_id is not null do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_revenue_snapshot_guard_and_case on public.revenue_account_snapshot;
create trigger trg_revenue_snapshot_guard_and_case
after insert on public.revenue_account_snapshot
for each row execute function public.revenue_snapshot_guard_and_case();

create or replace function public.resolve_revenue_liability(
  p_case_id uuid,
  p_liability_status text,
  p_suppress_automation boolean,
  p_note text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_case public.revenue_collection_case%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then
    raise exception 'MFA assurance level 2 required';
  end if;
  if p_liability_status not in ('unresolved','scheme_verified','patient_verified','split_verified','credit','zero_balance') then
    raise exception 'Invalid liability status';
  end if;

  select * into v_case from public.revenue_collection_case where id=p_case_id for update;
  if not found then raise exception 'Revenue case not found or not accessible'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_case.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  if p_liability_status='unresolved' and p_suppress_automation=false then
    raise exception 'Automation cannot be enabled while liability remains unresolved';
  end if;

  update public.revenue_collection_case
  set liability_status=p_liability_status,
      suppress_automation=p_suppress_automation,
      suppression_reason=case when p_suppress_automation then coalesce(p_note,suppression_reason,'Manual suppression') else null end,
      case_status=case
        when p_liability_status in ('credit','zero_balance') then 'suppressed'
        when p_suppress_automation then case_status
        when case_status='review_required' then 'ready_for_contact'
        else case_status
      end,
      notes=case when p_note is null then notes else concat_ws(E'\n',notes,p_note) end,
      updated_at=now()
  where id=p_case_id;

  return p_case_id;
end;
$$;

revoke all on function public.resolve_revenue_liability(uuid,text,boolean,text) from public,anon;
grant execute on function public.resolve_revenue_liability(uuid,text,boolean,text) to authenticated;

commit;
