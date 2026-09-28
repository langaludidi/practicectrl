
begin;

create table if not exists public.vericlaim_scheme_credits_staging (
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete cascade,
  row_number integer not null,
  scheme_name text,
  account_ref text,
  file_ref text,
  invoice_number text,
  scheme_credit_amount numeric(14,2),
  parse_status text not null default 'valid' check (parse_status in ('valid','invalid')),
  parse_error text,
  raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.vericlaim_receipt_type_summary_staging (
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete cascade,
  row_number integer not null,
  payment_type text,
  received_amount numeric(14,2),
  parse_status text not null default 'valid' check (parse_status in ('valid','invalid')),
  parse_error text,
  raw_row jsonb not null default '{}'::jsonb,
  primary key(import_batch_id,row_number)
);

create table if not exists public.vericlaim_scheme_credit_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete restrict,
  scheme_name text,
  account_ref text,
  file_ref text,
  invoice_number text,
  scheme_credit_amount numeric(14,2) not null,
  created_at timestamptz not null default now(),
  unique(import_batch_id,invoice_number,account_ref)
);
create index if not exists vericlaim_scheme_credit_practice_idx on public.vericlaim_scheme_credit_snapshot(practice_id,created_at desc);
create index if not exists vericlaim_scheme_credit_patient_idx on public.vericlaim_scheme_credit_snapshot(patient_id) where patient_id is not null;

create table if not exists public.vericlaim_receipt_type_summary_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete restrict,
  payment_type text not null,
  received_amount numeric(14,2) not null,
  source_scope_start date,
  source_scope_end date,
  created_at timestamptz not null default now(),
  unique(import_batch_id,payment_type)
);
create index if not exists vericlaim_receipt_summary_practice_idx on public.vericlaim_receipt_type_summary_snapshot(practice_id,created_at desc);

alter table public.vericlaim_scheme_credits_staging enable row level security;
alter table public.vericlaim_receipt_type_summary_staging enable row level security;
alter table public.vericlaim_scheme_credit_snapshot enable row level security;
alter table public.vericlaim_receipt_type_summary_snapshot enable row level security;

revoke all on table public.vericlaim_scheme_credits_staging from anon,authenticated;
revoke all on table public.vericlaim_receipt_type_summary_staging from anon,authenticated;
revoke all on table public.vericlaim_scheme_credit_snapshot from anon,authenticated;
revoke all on table public.vericlaim_receipt_type_summary_snapshot from anon,authenticated;

grant select on table public.vericlaim_scheme_credit_snapshot to authenticated;
grant select on table public.vericlaim_receipt_type_summary_snapshot to authenticated;

create policy vericlaim_credits_staging_deny_client on public.vericlaim_scheme_credits_staging for all to anon,authenticated using(false) with check(false);
create policy vericlaim_receipt_summary_staging_deny_client on public.vericlaim_receipt_type_summary_staging for all to anon,authenticated using(false) with check(false);

create policy vericlaim_credit_finance_read on public.vericlaim_scheme_credit_snapshot for select to authenticated
using (exists (
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.practice_id=vericlaim_scheme_credit_snapshot.practice_id and m.active
   and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy vericlaim_receipt_summary_finance_read on public.vericlaim_receipt_type_summary_snapshot for select to authenticated
using (exists (
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.practice_id=vericlaim_receipt_type_summary_snapshot.practice_id and m.active
   and m.role in ('billing','practice_manager','system_admin','auditor')
));

create or replace function public.promote_vericlaim_import(
  p_import_batch_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_batch public.vericlaim_import_batch%rowtype;
  v_patient uuid;
  r record;
  v_count integer := 0;
  v_contacts integer := 0;
begin
  select * into v_batch from public.vericlaim_import_batch where id=p_import_batch_id for update;
  if not found then raise exception 'Import batch not found'; end if;
  if v_batch.status <> 'validated' then raise exception 'Import batch must be validated before promotion'; end if;
  if v_batch.rejected_row_count <> 0 then raise exception 'Import batch contains rejected rows'; end if;

  if v_batch.report_type='AGE_ANALYSIS' then
    for r in select * from public.vericlaim_age_analysis_staging where import_batch_id=p_import_batch_id and parse_status='valid'
    loop
      v_patient := public.ensure_vericlaim_patient(v_batch.practice_id,r.account_ref,r.file_ref,r.patient_name,coalesce(v_batch.snapshot_at,v_batch.created_at));
      if v_patient is not null then
        if nullif(trim(coalesce(r.cell_no,'')),'') is not null and not exists(
          select 1 from public.crm_contact_point where patient_id=v_patient and contact_type='mobile' and value=r.cell_no
        ) then
          insert into public.crm_contact_point(patient_id,contact_type,value,is_primary,source_system,source_last_seen_at)
          values(v_patient,'mobile',r.cell_no,true,'VeriClaim',coalesce(v_batch.snapshot_at,v_batch.created_at));
          v_contacts:=v_contacts+1;
        end if;
        if nullif(trim(coalesce(r.email,'')),'') is not null and not exists(
          select 1 from public.crm_contact_point where patient_id=v_patient and contact_type='email' and lower(value)=lower(r.email)
        ) then
          insert into public.crm_contact_point(patient_id,contact_type,value,is_primary,source_system,source_last_seen_at)
          values(v_patient,'email',r.email,true,'VeriClaim',coalesce(v_batch.snapshot_at,v_batch.created_at));
          v_contacts:=v_contacts+1;
        end if;
      end if;

      insert into public.revenue_account_snapshot(
        practice_id,patient_id,import_batch_id,snapshot_at,patient_name_snapshot,account_ref,file_ref,scheme_name_snapshot,
        days_120_plus,days_90,days_60,days_30,current_amount,total_amount,liability_status,collection_suppressed,suppression_reason
      ) values(
        v_batch.practice_id,v_patient,p_import_batch_id,coalesce(v_batch.snapshot_at,v_batch.created_at),r.patient_name,r.account_ref,r.file_ref,r.scheme_name,
        coalesce(r.days_120_plus,0),coalesce(r.days_90,0),coalesce(r.days_60,0),coalesce(r.days_30,0),coalesce(r.current_amount,0),coalesce(r.total_amount,0),
        case when coalesce(r.total_amount,0)=0 then 'zero_balance' when coalesce(r.total_amount,0)<0 then 'credit' else 'unresolved' end,
        true,
        case when coalesce(r.total_amount,0)<0 then 'Credit balance requires review'
             when coalesce(r.total_amount,0)=0 then 'Zero balance'
             else 'Patient-versus-scheme liability not verified from Age Analysis alone' end
      ) on conflict(import_batch_id,account_ref,file_ref,patient_name_snapshot) do nothing;
      v_count:=v_count+1;
    end loop;

  elsif v_batch.report_type='INVOICE_ACTIVITY' then
    for r in
      select invoice_number,max(treatment_date) treatment_date,max(patient_name) patient_name,max(account_ref) account_ref,
             max(coalesce(patient_amount,0)) patient_amount,max(coalesce(funder_amount,0)) funder_amount,
             max(coalesce(total_amount,0)) total_amount,max(coalesce(received_amount,0)) received_amount,
             max(coalesce(paid_amount,0)) paid_amount,sum(coalesce(journaled_amount,0)) journaled_amount,
             max(coalesce(outstanding_amount,0)) outstanding_amount,max(age_days) age_days
      from public.vericlaim_invoice_activity_staging
      where import_batch_id=p_import_batch_id and parse_status='valid' and invoice_number is not null
      group by invoice_number
    loop
      v_patient := public.ensure_vericlaim_patient(v_batch.practice_id,r.account_ref,null,r.patient_name,v_batch.created_at);
      insert into public.vericlaim_invoice_snapshot(
        practice_id,patient_id,import_batch_id,invoice_number,treatment_date,patient_name_snapshot,account_ref,
        patient_amount,funder_amount,total_amount,received_amount,paid_amount,journaled_amount,outstanding_amount,age_days,
        source_scope_start,source_scope_end
      ) values(
        v_batch.practice_id,v_patient,p_import_batch_id,r.invoice_number,r.treatment_date,r.patient_name,r.account_ref,
        r.patient_amount,r.funder_amount,r.total_amount,r.received_amount,r.paid_amount,r.journaled_amount,r.outstanding_amount,r.age_days,
        v_batch.period_start,v_batch.period_end
      ) on conflict(import_batch_id,invoice_number) do nothing;
      v_count:=v_count+1;
    end loop;

  elsif v_batch.report_type='FUNDER_RECEIPTS' then
    insert into public.vericlaim_funder_receipt(practice_id,import_batch_id,receipt_number,medical_scheme,receipt_date,capture_date,receipt_amount)
    select v_batch.practice_id,p_import_batch_id,receipt_number,max(medical_scheme),max(receipt_date),max(capture_date),max(coalesce(receipt_amount,0))
    from public.vericlaim_funder_receipts_staging
    where import_batch_id=p_import_batch_id and parse_status='valid' and receipt_number is not null
    group by receipt_number
    on conflict(import_batch_id,receipt_number) do nothing;

    for r in
      select s.*,fr.id receipt_id
      from public.vericlaim_funder_receipts_staging s
      join public.vericlaim_funder_receipt fr on fr.import_batch_id=s.import_batch_id and fr.receipt_number=s.receipt_number
      where s.import_batch_id=p_import_batch_id and s.parse_status='valid'
    loop
      v_patient:=public.ensure_vericlaim_patient(v_batch.practice_id,r.account_ref,r.file_ref,r.patient_name,v_batch.created_at);
      insert into public.vericlaim_funder_receipt_allocation(
        receipt_id,patient_id,account_ref,file_ref,patient_name_snapshot,scheme_option,invoice_number,claim_number,
        treatment_date,invoice_date,scheme_liable,scheme_paid,scheme_nett_amount,source_row_number
      ) values(
        r.receipt_id,v_patient,r.account_ref,r.file_ref,r.patient_name,r.scheme_option,r.invoice_number,r.claim_number,
        r.treatment_date,r.invoice_date,r.scheme_liable,r.scheme_paid,r.scheme_nett_amount,r.row_number
      ) on conflict(receipt_id,source_row_number) do nothing;
      v_count:=v_count+1;
    end loop;

  elsif v_batch.report_type='SCHEME_CLAIMS' then
    for r in select * from public.vericlaim_scheme_claims_staging where import_batch_id=p_import_batch_id and parse_status='valid'
    loop
      v_patient:=public.ensure_vericlaim_patient(v_batch.practice_id,r.account_ref,r.file_ref,r.patient_surname,v_batch.created_at);
      insert into public.vericlaim_scheme_claim_snapshot(
        practice_id,patient_id,import_batch_id,scheme_name,invoice_number,invoice_date,treatment_date,
        account_ref,file_ref,patient_surname,claimed_amount,outstanding_amount,source_scope_start,source_scope_end
      ) values(
        v_batch.practice_id,v_patient,p_import_batch_id,r.scheme_name,r.invoice_number,r.invoice_date,r.treatment_date,
        r.account_ref,r.file_ref,r.patient_surname,r.claimed_amount,r.outstanding_amount,v_batch.period_start,v_batch.period_end
      ) on conflict(import_batch_id,invoice_number,account_ref) do nothing;
      v_count:=v_count+1;
    end loop;

  elsif v_batch.report_type='SCHEME_PATIENT_POPULATION' then
    insert into public.vericlaim_scheme_population_snapshot(practice_id,import_batch_id,scheme_name,scheme_option,total_patients)
    select v_batch.practice_id,p_import_batch_id,scheme_name,scheme_option,total_patients
    from public.vericlaim_scheme_population_staging
    where import_batch_id=p_import_batch_id and parse_status='valid'
    on conflict(import_batch_id,scheme_name,scheme_option) do nothing;
    get diagnostics v_count = row_count;

  elsif v_batch.report_type='SCHEME_CREDITS' then
    for r in select * from public.vericlaim_scheme_credits_staging where import_batch_id=p_import_batch_id and parse_status='valid'
    loop
      v_patient:=public.ensure_vericlaim_patient(v_batch.practice_id,r.account_ref,r.file_ref,coalesce(r.scheme_name,'VeriClaim credit account'),v_batch.created_at);
      insert into public.vericlaim_scheme_credit_snapshot(
        practice_id,patient_id,import_batch_id,scheme_name,account_ref,file_ref,invoice_number,scheme_credit_amount
      ) values(
        v_batch.practice_id,v_patient,p_import_batch_id,r.scheme_name,r.account_ref,r.file_ref,r.invoice_number,coalesce(r.scheme_credit_amount,0)
      ) on conflict(import_batch_id,invoice_number,account_ref) do nothing;

      update public.revenue_account_snapshot
      set collection_suppressed=true,
          suppression_reason='Scheme credit exists in the latest imported credit report'
      where practice_id=v_batch.practice_id and account_ref=r.account_ref and source_freshness_status='current';
      v_count:=v_count+1;
    end loop;

  elsif v_batch.report_type='RECEIPT_TYPE_SUMMARY' then
    insert into public.vericlaim_receipt_type_summary_snapshot(
      practice_id,import_batch_id,payment_type,received_amount,source_scope_start,source_scope_end
    )
    select v_batch.practice_id,p_import_batch_id,payment_type,coalesce(received_amount,0),v_batch.period_start,v_batch.period_end
    from public.vericlaim_receipt_type_summary_staging
    where import_batch_id=p_import_batch_id and parse_status='valid' and payment_type is not null
    on conflict(import_batch_id,payment_type) do nothing;
    get diagnostics v_count = row_count;

  else
    raise exception 'Promotion is not implemented for report type %',v_batch.report_type;
  end if;

  update public.vericlaim_import_batch
  set status='promoted',completed_at=now(),
      validation_summary=coalesce(validation_summary,'{}'::jsonb) || jsonb_build_object('promoted_rows',v_count,'contacts_added',v_contacts)
  where id=p_import_batch_id;

  update public.practice_import_file set status='promoted' where id=v_batch.import_file_id;

  return jsonb_build_object('report_type',v_batch.report_type,'promoted_rows',v_count,'contacts_added',v_contacts);
end;
$$;

revoke all on function public.promote_vericlaim_import(uuid,uuid) from public,anon,authenticated;
grant execute on function public.promote_vericlaim_import(uuid,uuid) to service_role;

commit;
