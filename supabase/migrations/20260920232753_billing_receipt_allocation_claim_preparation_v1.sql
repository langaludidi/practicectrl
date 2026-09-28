
begin;

create table if not exists public.billing_allocation_event (
  id uuid primary key default gen_random_uuid(),
  allocation_id uuid not null references public.billing_payment_allocation(id) on delete restrict,
  event_type text not null check (event_type in ('posted','reversed')),
  actor_user_id uuid references auth.users(id) on delete set null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists billing_allocation_event_allocation_idx
  on public.billing_allocation_event(allocation_id,created_at desc);
create index if not exists billing_allocation_event_actor_idx
  on public.billing_allocation_event(actor_user_id) where actor_user_id is not null;

alter table public.billing_allocation_event enable row level security;
revoke all on table public.billing_allocation_event from anon,authenticated;
grant select on table public.billing_allocation_event to authenticated;

create policy billing_allocation_event_finance_read
on public.billing_allocation_event for select to authenticated
using (exists (
  select 1
  from public.billing_payment_allocation a
  join public.billing_payment_receipt r on r.id=a.receipt_id
  join public.practice_staff_member m on m.practice_id=r.practice_id
  where a.id=billing_allocation_event.allocation_id
    and m.user_id=(select auth.uid()) and m.active
    and m.role in ('billing','practice_manager','system_admin','auditor')
));

create or replace function public.create_billing_receipt(
  p_practice_id uuid,
  p_patient_id uuid,
  p_medical_scheme_id uuid,
  p_payer_type text,
  p_receipt_number text,
  p_receipt_date date,
  p_amount numeric,
  p_payment_method text default null,
  p_external_reference text default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_payer_type not in ('patient','scheme','insurer','other') then raise exception 'Invalid payer type'; end if;
  if p_amount is null or p_amount=0 then raise exception 'Receipt amount cannot be zero'; end if;
  if length(trim(coalesce(p_receipt_number,'')))<1 then raise exception 'Receipt number is required'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  if p_patient_id is not null and not exists (
    select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id
  ) then raise exception 'Patient is not in this practice'; end if;

  insert into public.billing_payment_receipt(
    practice_id,patient_id,medical_scheme_id,payer_type,receipt_number,
    receipt_date,amount,payment_method,external_reference,source_system,created_by
  ) values(
    p_practice_id,p_patient_id,p_medical_scheme_id,p_payer_type,trim(p_receipt_number),
    coalesce(p_receipt_date,current_date),p_amount,p_payment_method,p_external_reference,'PracticeCtrl',v_user
  )
  returning id into v_id;

  return v_id;
end;
$$;
revoke all on function public.create_billing_receipt(uuid,uuid,uuid,text,text,date,numeric,text,text) from public,anon;
grant execute on function public.create_billing_receipt(uuid,uuid,uuid,text,text,date,numeric,text,text) to authenticated;

create or replace function public.allocate_billing_receipt(
  p_receipt_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_claim_id uuid default null,
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
  v_receipt public.billing_payment_receipt%rowtype;
  v_invoice public.billing_invoice%rowtype;
  v_allocated numeric(14,2);
  v_allocation_id uuid;
  v_new_received numeric(14,2);
  v_new_balance numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Allocation amount must be greater than zero'; end if;

  select * into v_receipt from public.billing_payment_receipt where id=p_receipt_id for update;
  if not found then raise exception 'Receipt not found or not accessible'; end if;

  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if v_invoice.practice_id<>v_receipt.practice_id then raise exception 'Receipt and invoice belong to different practices'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  if p_claim_id is not null and not exists (
    select 1 from public.claim_record c
    where c.id=p_claim_id and c.practice_id=v_invoice.practice_id
      and (c.invoice_id is null or c.invoice_id=v_invoice.id)
  ) then raise exception 'Claim link is not valid for this invoice/practice'; end if;

  select coalesce(sum(amount),0) into v_allocated
  from public.billing_payment_allocation
  where receipt_id=p_receipt_id and allocation_status='posted';

  if round(v_allocated+p_amount,2)>round(abs(v_receipt.amount),2) then
    raise exception 'Allocation exceeds the unallocated receipt amount';
  end if;
  if round(p_amount,2)>round(v_invoice.balance_amount,2) then
    raise exception 'Allocation exceeds the invoice balance';
  end if;

  insert into public.billing_payment_allocation(
    receipt_id,invoice_id,claim_id,amount,allocation_status,allocated_by,notes
  ) values(
    p_receipt_id,p_invoice_id,p_claim_id,p_amount,'posted',v_user,p_note
  ) returning id into v_allocation_id;

  v_new_received := v_invoice.received_amount + p_amount;
  v_new_balance := greatest(v_invoice.total_amount-v_new_received,0);

  update public.billing_invoice
  set received_amount=v_new_received,
      balance_amount=v_new_balance,
      status=case
        when v_new_balance=0 then 'paid'
        when v_invoice.status='draft' then 'draft'
        else 'part_paid'
      end,
      updated_at=now()
  where id=p_invoice_id;

  insert into public.billing_allocation_event(allocation_id,event_type,actor_user_id,reason,metadata)
  values(v_allocation_id,'posted',v_user,p_note,jsonb_build_object(
    'receipt_id',p_receipt_id,'invoice_id',p_invoice_id,'amount',p_amount
  ));

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'payment_allocated',v_user,jsonb_build_object(
    'allocation_id',v_allocation_id,'receipt_id',p_receipt_id,'amount',p_amount,'new_balance',v_new_balance
  ));

  return v_allocation_id;
end;
$$;
revoke all on function public.allocate_billing_receipt(uuid,uuid,numeric,uuid,text) from public,anon;
grant execute on function public.allocate_billing_receipt(uuid,uuid,numeric,uuid,text) to authenticated;

create or replace function public.reverse_billing_allocation(
  p_allocation_id uuid,
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
  v_alloc public.billing_payment_allocation%rowtype;
  v_invoice public.billing_invoice%rowtype;
  v_new_received numeric(14,2);
  v_new_balance numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reversal reason is required'; end if;

  select * into v_alloc from public.billing_payment_allocation where id=p_allocation_id for update;
  if not found then raise exception 'Allocation not found or not accessible'; end if;
  if v_alloc.allocation_status<>'posted' then raise exception 'Only posted allocations can be reversed'; end if;

  select * into v_invoice from public.billing_invoice where id=v_alloc.invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  v_new_received := greatest(v_invoice.received_amount-v_alloc.amount,0);
  v_new_balance := greatest(v_invoice.total_amount-v_new_received,0);

  update public.billing_payment_allocation
  set allocation_status='reversed'
  where id=p_allocation_id;

  update public.billing_invoice
  set received_amount=v_new_received,
      balance_amount=v_new_balance,
      status=case
        when v_new_balance=0 then 'paid'
        when v_invoice.finalised_at is not null and v_new_received>0 then 'part_paid'
        when v_invoice.finalised_at is not null then 'final'
        else 'draft'
      end,
      updated_at=now()
  where id=v_invoice.id;

  insert into public.billing_allocation_event(allocation_id,event_type,actor_user_id,reason,metadata)
  values(p_allocation_id,'reversed',v_user,trim(p_reason),jsonb_build_object(
    'amount',v_alloc.amount,'invoice_id',v_invoice.id,'new_balance',v_new_balance
  ));

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(v_invoice.id,'adjusted',v_user,jsonb_build_object(
    'allocation_id',p_allocation_id,'reversal',true,'amount',v_alloc.amount,'reason',trim(p_reason),'new_balance',v_new_balance
  ));

  return p_allocation_id;
end;
$$;
revoke all on function public.reverse_billing_allocation(uuid,text) from public,anon;
grant execute on function public.reverse_billing_allocation(uuid,text) to authenticated;

create or replace function public.prepare_claim_from_invoice(p_invoice_id uuid)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_invoice public.billing_invoice%rowtype;
  v_readiness jsonb;
  v_claim_id uuid;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;

  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  v_readiness := public.assess_claim_readiness(p_invoice_id);
  if coalesce((v_readiness->>'ready')::boolean,false)=false then
    raise exception 'Invoice is not claim-ready: %', coalesce(v_readiness->'reasons','[]'::jsonb)::text;
  end if;

  if exists(select 1 from public.claim_record c where c.invoice_id=p_invoice_id and c.claim_status not in ('cancelled','reversed')) then
    raise exception 'An active claim already exists for this invoice';
  end if;

  insert into public.claim_record(
    practice_id,invoice_id,patient_id,medical_scheme_id,medical_scheme_option_id,
    claim_status,service_from,service_to,total_claimed,created_by
  )
  values(
    v_invoice.practice_id,v_invoice.id,v_invoice.patient_id,v_invoice.medical_scheme_id,v_invoice.medical_scheme_option_id,
    'draft',v_invoice.invoice_date,v_invoice.invoice_date,v_invoice.scheme_portion,v_user
  )
  returning id into v_claim_id;

  insert into public.claim_line(
    claim_id,invoice_line_id,line_no,code_system,code,modifier_codes,diagnosis_codes,
    quantity,claimed_amount,status
  )
  select
    v_claim_id,l.id,l.line_no,l.code_system,l.code,l.modifier_codes,l.diagnosis_codes,
    l.quantity,l.line_amount,'draft'
  from public.billing_invoice_line l
  where l.invoice_id=p_invoice_id
    and coalesce((l.metadata->>'claim_eligible')::boolean,true)=true
  order by l.line_no;

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'validated',v_user,jsonb_build_object(
    'claim_id',v_claim_id,'claim_prepared',true
  ));

  return v_claim_id;
end;
$$;
revoke all on function public.prepare_claim_from_invoice(uuid) from public,anon;
grant execute on function public.prepare_claim_from_invoice(uuid) to authenticated;

commit;
