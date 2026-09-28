
create or replace function private.set_payer_remittance_variance_status_internal(
  p_variance_id uuid,
  p_status text,
  p_reason text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := (select auth.uid());
  v public.payer_remittance_variance%rowtype;
begin
  if v_user is null or coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then
    raise exception 'AAL2 authentication required';
  end if;
  if p_status not in ('accepted','disputed','recovered','written_off') then
    raise exception 'Invalid variance status';
  end if;
  if p_reason is not null and p_reason not in ('tariff_difference','code_rejection','modifier_omission','benefit_exhaustion','copayment','network_restriction','scheme_underpayment','contractual_adjustment','authorisation','other') then
    raise exception 'Invalid variance reason';
  end if;
  select * into v from public.payer_remittance_variance where id=p_variance_id for update;
  if not found then raise exception 'Variance not found'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;
  if p_status='written_off' and coalesce(length(trim(p_notes)),0)<5 then
    raise exception 'A write-off requires a review note';
  end if;
  update public.payer_remittance_variance
     set status=p_status,
         variance_reason=coalesce(p_reason,variance_reason),
         notes=case when p_notes is null or trim(p_notes)='' then notes else concat_ws(E'\n',notes,p_notes) end,
         reviewed_by=v_user,
         reviewed_at=now()
   where id=p_variance_id;
  return p_variance_id;
end $$;

create or replace function public.set_payer_remittance_variance_status(
  p_variance_id uuid,
  p_status text,
  p_reason text default null,
  p_notes text default null
) returns uuid
language sql
set search_path=''
as $$ select private.set_payer_remittance_variance_status_internal(p_variance_id,p_status,p_reason,p_notes) $$;

revoke all on function private.set_payer_remittance_variance_status_internal(uuid,text,text,text) from public,anon;
revoke all on function public.set_payer_remittance_variance_status(uuid,text,text,text) from public,anon;
grant execute on function private.set_payer_remittance_variance_status_internal(uuid,text,text,text) to authenticated;
grant execute on function public.set_payer_remittance_variance_status(uuid,text,text,text) to authenticated,service_role;

