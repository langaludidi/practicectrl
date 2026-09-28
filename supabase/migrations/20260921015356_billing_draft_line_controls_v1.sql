
begin;

create or replace function public.add_practice_custom_invoice_line(
  p_invoice_id uuid,
  p_description text,
  p_amount numeric
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_invoice public.billing_invoice%rowtype;
  v_line_no integer;
  v_line_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
  if length(trim(coalesce(p_description,'')))<2 then raise exception 'Description is required'; end if;

  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if v_invoice.status<>'draft' then raise exception 'Lines can be edited only while the invoice is draft'; end if;
  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  select coalesce(max(line_no),0)+1 into v_line_no
  from public.billing_invoice_line where invoice_id=p_invoice_id;

  insert into public.billing_invoice_line(
    invoice_id,line_no,code_system,code,description_snapshot,
    quantity,unit_amount,line_amount,metadata
  ) values(
    p_invoice_id,v_line_no,'PRACTICE_CUSTOM','CUSTOM',trim(p_description),
    1,p_amount,p_amount,jsonb_build_object('claim_eligible',false,'source','PracticeCtrl custom draft')
  ) returning id into v_line_id;

  update public.billing_invoice
  set total_amount=total_amount+p_amount,
      patient_portion=patient_portion+p_amount,
      balance_amount=balance_amount+p_amount,
      updated_at=now()
  where id=p_invoice_id;

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'line_added',v_user,jsonb_build_object(
    'invoice_line_id',v_line_id,'line_no',v_line_no,'amount',p_amount,'claim_eligible',false
  ));

  return v_line_id;
end;
$$;
revoke all on function public.add_practice_custom_invoice_line(uuid,text,numeric) from public,anon;
grant execute on function public.add_practice_custom_invoice_line(uuid,text,numeric) to authenticated;

create or replace function public.remove_practice_custom_invoice_line(
  p_invoice_line_id uuid,
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
  v_line public.billing_invoice_line%rowtype;
  v_invoice public.billing_invoice%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Removal reason is required'; end if;

  select * into v_line from public.billing_invoice_line where id=p_invoice_line_id for update;
  if not found then raise exception 'Invoice line not found or not accessible'; end if;
  select * into v_invoice from public.billing_invoice where id=v_line.invoice_id for update;
  if v_invoice.status<>'draft' then raise exception 'Lines can be removed only while the invoice is draft'; end if;
  if v_line.code_system<>'PRACTICE_CUSTOM' or coalesce((v_line.metadata->>'claim_eligible')::boolean,true) then
    raise exception 'Only non-claimable PracticeCtrl custom draft lines can be removed with this action';
  end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  if (select count(*) from public.billing_invoice_line where invoice_id=v_invoice.id)<=1 then
    raise exception 'An invoice must retain at least one line';
  end if;

  delete from public.billing_invoice_line where id=p_invoice_line_id;

  update public.billing_invoice
  set total_amount=greatest(total_amount-v_line.line_amount,0),
      patient_portion=greatest(patient_portion-v_line.line_amount,0),
      balance_amount=greatest(balance_amount-v_line.line_amount,0),
      updated_at=now()
  where id=v_invoice.id;

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(v_invoice.id,'line_removed',v_user,jsonb_build_object(
    'invoice_line_id',p_invoice_line_id,'line_no',v_line.line_no,
    'amount',v_line.line_amount,'reason',trim(p_reason)
  ));

  return p_invoice_line_id;
end;
$$;
revoke all on function public.remove_practice_custom_invoice_line(uuid,text) from public,anon;
grant execute on function public.remove_practice_custom_invoice_line(uuid,text) to authenticated;

commit;
