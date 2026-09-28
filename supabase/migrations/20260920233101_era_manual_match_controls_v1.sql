
begin;

alter table public.remittance_match
  add column if not exists unmatched_reason text;

create or replace function public.manual_match_remittance_line(
  p_remittance_line_id uuid,
  p_claim_id uuid,
  p_claim_line_id uuid default null,
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
  v_line public.remittance_line%rowtype;
  v_era public.remittance_advice%rowtype;
  v_claim public.claim_record%rowtype;
  v_match_id uuid;
  v_total integer;
  v_matched integer;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_line from public.remittance_line where id=p_remittance_line_id for update;
  if not found then raise exception 'Remittance line not found or not accessible'; end if;

  select * into v_era from public.remittance_advice where id=v_line.remittance_id for update;
  if not found then raise exception 'Remittance not found'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_era.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  select * into v_claim from public.claim_record where id=p_claim_id;
  if not found or v_claim.practice_id<>v_era.practice_id then
    raise exception 'Claim is not in the same practice';
  end if;

  if p_claim_line_id is not null and not exists (
    select 1 from public.claim_line l where l.id=p_claim_line_id and l.claim_id=p_claim_id
  ) then raise exception 'Claim line does not belong to the selected claim'; end if;

  update public.remittance_match
  set match_status='rejected',
      matched_by=v_user,
      matched_at=now(),
      notes=concat_ws(E'\n',notes,'Superseded by a later manual match')
  where remittance_line_id=p_remittance_line_id
    and match_status in ('auto_exact','auto_probable','manual');

  update public.remittance_line
  set claim_id=p_claim_id,
      claim_line_id=p_claim_line_id
  where id=p_remittance_line_id;

  insert into public.remittance_match(
    remittance_line_id,claim_id,claim_line_id,match_status,match_method,
    matched_by,matched_at,notes
  ) values(
    p_remittance_line_id,p_claim_id,p_claim_line_id,'manual','staff_review',
    v_user,now(),p_note
  )
  returning id into v_match_id;

  select count(*),count(*) filter (where claim_id is not null)
  into v_total,v_matched
  from public.remittance_line
  where remittance_id=v_era.id;

  update public.remittance_advice
  set status=case when v_total>0 and v_matched=v_total then 'matched' else 'partially_matched' end
  where id=v_era.id
    and status in ('received','parsed','partially_matched','matched','exception');

  return v_match_id;
end;
$$;
revoke all on function public.manual_match_remittance_line(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.manual_match_remittance_line(uuid,uuid,uuid,text) to authenticated;

create or replace function public.unmatch_remittance_line(
  p_remittance_line_id uuid,
  p_reason text
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_line public.remittance_line%rowtype;
  v_era public.remittance_advice%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Unmatch reason is required'; end if;

  select * into v_line from public.remittance_line where id=p_remittance_line_id for update;
  if not found then raise exception 'Remittance line not found or not accessible'; end if;
  select * into v_era from public.remittance_advice where id=v_line.remittance_id for update;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_era.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  update public.remittance_match
  set match_status='unmatched',
      matched_by=v_user,
      matched_at=now(),
      unmatched_reason=trim(p_reason),
      notes=concat_ws(E'\n',notes,'Manual unmatch: '||trim(p_reason))
  where remittance_line_id=p_remittance_line_id
    and match_status in ('auto_exact','auto_probable','manual');

  update public.remittance_line
  set claim_id=null,claim_line_id=null
  where id=p_remittance_line_id;

  update public.remittance_advice
  set status='partially_matched'
  where id=v_era.id and status in ('matched','reconciled','partially_matched');

  return p_remittance_line_id;
end;
$$;
revoke all on function public.unmatch_remittance_line(uuid,text) from public,anon;
grant execute on function public.unmatch_remittance_line(uuid,text) to authenticated;

commit;
