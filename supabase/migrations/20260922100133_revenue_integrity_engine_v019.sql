
create table if not exists public.revenue_integrity_assessment(
 id uuid primary key default gen_random_uuid(),
 practice_id uuid not null references public.practice(id) on delete cascade,
 invoice_id uuid not null references public.billing_invoice(id) on delete cascade,
 claim_id uuid references public.claim_record(id) on delete cascade,
 assessment_type text not null default 'pre_claim' check(assessment_type in('pre_claim','pre_submission')),
 status text not null check(status in('ready','blocked','review')),
 score integer not null check(score between 0 and 100),
 blocking_count integer not null default 0,
 warning_count integer not null default 0,
 findings jsonb not null default '[]'::jsonb,
 summary jsonb not null default '{}'::jsonb,
 assessed_by uuid references auth.users(id) on delete set null,
 assessed_at timestamptz not null default now()
);
alter table public.revenue_integrity_assessment enable row level security;
create index if not exists revenue_integrity_invoice_idx on public.revenue_integrity_assessment(practice_id,invoice_id,assessed_at desc);
create index if not exists revenue_integrity_claim_idx on public.revenue_integrity_assessment(practice_id,claim_id,assessed_at desc) where claim_id is not null;
create policy revenue_integrity_staff_read on public.revenue_integrity_assessment for select to authenticated using(exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=revenue_integrity_assessment.practice_id and m.active));
grant select on public.revenue_integrity_assessment to authenticated;

create or replace function public.assess_revenue_integrity(p_invoice_id uuid,p_claim_id uuid default null,p_persist boolean default false)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid()); i public.billing_invoice%rowtype; c public.claim_record%rowtype; base jsonb; f jsonb:='[]'::jsonb; blocks int:=0; warns int:=0; score int:=100; st text; v_membership boolean:=false; v_auth boolean:=true; v_id uuid;
begin
 select * into i from public.billing_invoice where id=p_invoice_id;
 if not found then return jsonb_build_object('status','blocked','score',0,'findings',jsonb_build_array(jsonb_build_object('severity','blocker','code','INVOICE_NOT_FOUND','message','Invoice not found or inaccessible'))); end if;
 if v_user is null or not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=i.practice_id and m.active and m.role in('billing','reception','practice_manager','clinical_admin','system_admin','auditor')) then return jsonb_build_object('status','blocked','score',0,'findings',jsonb_build_array(jsonb_build_object('severity','blocker','code','ROLE_REQUIRED','message','Authorised practice role required'))); end if;
 base:=public.assess_claim_readiness(p_invoice_id);
 for f in select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('severity','blocker','code','CLAIM_READINESS','message',value#>>'{}') x from jsonb_array_elements(coalesce(base->'reasons','[]'::jsonb))) s loop null; end loop;
 blocks:=jsonb_array_length(f);
 if i.patient_id is null then f:=f||jsonb_build_array(jsonb_build_object('severity','blocker','code','PATIENT_LINK','message','Patient link is required'));blocks:=blocks+1;end if;
 if exists(select 1 from public.billing_invoice_line l where l.invoice_id=i.id and l.claim_eligible and (l.service_date is null or cardinality(l.diagnosis_codes)=0 or nullif(trim(l.code),'') is null)) then f:=f||jsonb_build_array(jsonb_build_object('severity','blocker','code','LINE_COMPLETENESS','message','Claim-eligible lines require service date, procedure code and diagnosis coding'));blocks:=blocks+1;end if;
 if exists(select 1 from public.billing_invoice_line l where l.invoice_id=i.id and l.claim_eligible and l.line_amount<=0) then f:=f||jsonb_build_array(jsonb_build_object('severity','blocker','code','INVALID_AMOUNT','message','Claim-eligible line amount must be greater than zero'));blocks:=blocks+1;end if;
 if i.scheme_portion>0 and i.patient_id is not null and i.medical_scheme_id is not null then
  select exists(select 1 from public.crm_patient_scheme_membership m where m.practice_id=i.practice_id and m.patient_id=i.patient_id and m.medical_scheme_id=i.medical_scheme_id and (i.medical_scheme_option_id is null or m.medical_scheme_option_id=i.medical_scheme_option_id) and m.membership_status='active_verified' and (m.effective_from is null or m.effective_from<=i.invoice_date) and (m.effective_to is null or m.effective_to>=i.invoice_date)) into v_membership;
  if not v_membership then f:=f||jsonb_build_array(jsonb_build_object('severity','blocker','code','MEMBERSHIP_UNVERIFIED','message','Scheme liability exists but active membership is not verified for the invoice date'));blocks:=blocks+1;end if;
 end if;
 if i.scheme_authorisation_id is not null then
  select exists(select 1 from public.scheme_authorisation a where a.id=i.scheme_authorisation_id and a.practice_id=i.practice_id and a.patient_id=i.patient_id and a.status in('approved','partially_approved') and nullif(trim(a.authorisation_number),'') is not null and (a.effective_from is null or a.effective_from<=i.invoice_date) and (a.effective_to is null or a.effective_to>=i.invoice_date)) into v_auth;
  if not v_auth then f:=f||jsonb_build_array(jsonb_build_object('severity','blocker','code','AUTHORISATION_INVALID','message','Linked authorisation is not valid for the invoice date'));blocks:=blocks+1;end if;
 end if;
 if i.scheme_portion+i.patient_portion<>i.total_amount then f:=f||jsonb_build_array(jsonb_build_object('severity','warning','code','LIABILITY_SPLIT','message','Scheme and patient liability do not equal invoice total'));warns:=warns+1;end if;
 if i.balance_amount<0 then f:=f||jsonb_build_array(jsonb_build_object('severity','warning','code','NEGATIVE_BALANCE','message','Invoice has a negative balance requiring review'));warns:=warns+1;end if;
 if p_claim_id is not null then select * into c from public.claim_record where id=p_claim_id and practice_id=i.practice_id and invoice_id=i.id;if not found then f:=f||jsonb_build_array(jsonb_build_object('severity','blocker','code','CLAIM_LINK','message','Claim is not linked to this invoice'));blocks:=blocks+1;else base:=public.assess_claim_submission_readiness(c.id);f:=f||(select coalesce(jsonb_agg(jsonb_build_object('severity','blocker','code','SUBMISSION_READINESS','message',value#>>'{}')),'[]'::jsonb) from jsonb_array_elements(coalesce(base->'reasons','[]'::jsonb)));blocks:=blocks+jsonb_array_length(coalesce(base->'reasons','[]'::jsonb));end if;end if;
 score:=greatest(0,100-(blocks*20)-(warns*5));st:=case when blocks>0 then 'blocked' when warns>0 then 'review' else 'ready' end;
 base:=jsonb_build_object('status',st,'score',score,'blocking_count',blocks,'warning_count',warns,'findings',f,'invoice_id',i.id,'claim_id',p_claim_id,'verified_membership_active',v_membership,'linked_authorisation_valid',v_auth,'assessed_at',now());
 if p_persist then if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 required to persist revenue integrity assessment';end if;insert into public.revenue_integrity_assessment(practice_id,invoice_id,claim_id,assessment_type,status,score,blocking_count,warning_count,findings,summary,assessed_by) values(i.practice_id,i.id,p_claim_id,case when p_claim_id is null then 'pre_claim' else 'pre_submission' end,st,score,blocks,warns,f,base,v_user) returning id into v_id;base:=base||jsonb_build_object('assessment_id',v_id);end if;
 return base;
end $$;
revoke all on function public.assess_revenue_integrity(uuid,uuid,boolean) from public,anon;
grant execute on function public.assess_revenue_integrity(uuid,uuid,boolean) to authenticated;

