
begin;

create table if not exists public.practice_import_file (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  source_system text not null,
  report_type text,
  bucket_id text not null default 'practice-import-files',
  object_path text not null,
  original_filename text not null,
  mime_type text,
  byte_size bigint not null check (byte_size > 0),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  uploaded_by uuid references auth.users(id) on delete set null,
  uploaded_at timestamptz not null default now(),
  status text not null default 'uploaded' check (status in ('uploaded','parsed','promoted','rejected')),
  unique(practice_id,source_system,sha256),
  unique(bucket_id,object_path)
);
create index if not exists practice_import_file_practice_idx on public.practice_import_file(practice_id,uploaded_at desc);
create index if not exists practice_import_file_uploaded_by_idx on public.practice_import_file(uploaded_by) where uploaded_by is not null;

alter table public.vericlaim_import_batch
  add column if not exists import_file_id uuid references public.practice_import_file(id) on delete restrict;
create index if not exists vericlaim_import_file_idx on public.vericlaim_import_batch(import_file_id) where import_file_id is not null;

create table if not exists public.vericlaim_invoice_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete restrict,
  invoice_number text not null,
  treatment_date date,
  patient_name_snapshot text,
  account_ref text,
  patient_amount numeric(14,2) not null default 0,
  funder_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,
  received_amount numeric(14,2) not null default 0,
  paid_amount numeric(14,2) not null default 0,
  journaled_amount numeric(14,2) not null default 0,
  outstanding_amount numeric(14,2) not null default 0,
  age_days integer,
  source_scope_start date,
  source_scope_end date,
  created_at timestamptz not null default now(),
  unique(import_batch_id,invoice_number)
);
create index if not exists vericlaim_invoice_snapshot_practice_idx on public.vericlaim_invoice_snapshot(practice_id,treatment_date desc);
create index if not exists vericlaim_invoice_snapshot_patient_idx on public.vericlaim_invoice_snapshot(patient_id,treatment_date desc) where patient_id is not null;
create index if not exists vericlaim_invoice_snapshot_account_idx on public.vericlaim_invoice_snapshot(practice_id,account_ref) where account_ref is not null;

create table if not exists public.vericlaim_funder_receipt (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete restrict,
  receipt_number text not null,
  medical_scheme text,
  receipt_date date,
  capture_date date,
  receipt_amount numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  unique(import_batch_id,receipt_number)
);
create index if not exists vericlaim_funder_receipt_practice_idx on public.vericlaim_funder_receipt(practice_id,receipt_date desc);

create table if not exists public.vericlaim_funder_receipt_allocation (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.vericlaim_funder_receipt(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  account_ref text,
  file_ref text,
  patient_name_snapshot text,
  scheme_option text,
  invoice_number text,
  claim_number text,
  treatment_date date,
  invoice_date date,
  scheme_liable numeric(14,2),
  scheme_paid numeric(14,2),
  scheme_nett_amount numeric(14,2),
  source_row_number integer,
  created_at timestamptz not null default now(),
  unique(receipt_id,source_row_number)
);
create index if not exists vericlaim_receipt_alloc_receipt_idx on public.vericlaim_funder_receipt_allocation(receipt_id);
create index if not exists vericlaim_receipt_alloc_patient_idx on public.vericlaim_funder_receipt_allocation(patient_id) where patient_id is not null;
create index if not exists vericlaim_receipt_alloc_invoice_idx on public.vericlaim_funder_receipt_allocation(invoice_number) where invoice_number is not null;

create table if not exists public.vericlaim_scheme_claim_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  patient_id uuid references public.crm_patient(id) on delete set null,
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete restrict,
  scheme_name text,
  invoice_number text,
  invoice_date date,
  treatment_date date,
  account_ref text,
  file_ref text,
  patient_surname text,
  claimed_amount numeric(14,2),
  outstanding_amount numeric(14,2),
  source_scope_start date,
  source_scope_end date,
  created_at timestamptz not null default now(),
  unique(import_batch_id,invoice_number,account_ref)
);
create index if not exists vericlaim_scheme_claim_practice_idx on public.vericlaim_scheme_claim_snapshot(practice_id,treatment_date desc);
create index if not exists vericlaim_scheme_claim_patient_idx on public.vericlaim_scheme_claim_snapshot(patient_id) where patient_id is not null;

create table if not exists public.vericlaim_scheme_population_snapshot (
  id uuid primary key default gen_random_uuid(),
  practice_id uuid not null references public.practice(id) on delete cascade,
  import_batch_id uuid not null references public.vericlaim_import_batch(id) on delete restrict,
  scheme_name text not null,
  scheme_option text not null,
  total_patients integer not null check (total_patients >= 0),
  created_at timestamptz not null default now(),
  unique(import_batch_id,scheme_name,scheme_option)
);
create index if not exists vericlaim_population_practice_idx on public.vericlaim_scheme_population_snapshot(practice_id,total_patients desc);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types,versioning_status)
values(
  'practice-import-files','practice-import-files',false,52428800,
  array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-excel','text/csv','application/octet-stream'],
  'DISABLED'
)
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

alter table public.practice_import_file enable row level security;
alter table public.vericlaim_invoice_snapshot enable row level security;
alter table public.vericlaim_funder_receipt enable row level security;
alter table public.vericlaim_funder_receipt_allocation enable row level security;
alter table public.vericlaim_scheme_claim_snapshot enable row level security;
alter table public.vericlaim_scheme_population_snapshot enable row level security;

revoke all on table public.practice_import_file from anon,authenticated;
revoke all on table public.vericlaim_invoice_snapshot from anon,authenticated;
revoke all on table public.vericlaim_funder_receipt from anon,authenticated;
revoke all on table public.vericlaim_funder_receipt_allocation from anon,authenticated;
revoke all on table public.vericlaim_scheme_claim_snapshot from anon,authenticated;
revoke all on table public.vericlaim_scheme_population_snapshot from anon,authenticated;

grant select on table public.practice_import_file to authenticated;
grant select on table public.vericlaim_invoice_snapshot to authenticated;
grant select on table public.vericlaim_funder_receipt to authenticated;
grant select on table public.vericlaim_funder_receipt_allocation to authenticated;
grant select on table public.vericlaim_scheme_claim_snapshot to authenticated;
grant select on table public.vericlaim_scheme_population_snapshot to authenticated;

create policy practice_import_file_finance_read on public.practice_import_file for select to authenticated
using (exists (
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.practice_id=practice_import_file.practice_id and m.active
   and m.role in ('billing','practice_manager','system_admin','auditor')
));

create policy vericlaim_invoice_snapshot_finance_read on public.vericlaim_invoice_snapshot for select to authenticated
using (exists (
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.practice_id=vericlaim_invoice_snapshot.practice_id and m.active
   and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy vericlaim_receipt_finance_read on public.vericlaim_funder_receipt for select to authenticated
using (exists (
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.practice_id=vericlaim_funder_receipt.practice_id and m.active
   and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy vericlaim_receipt_alloc_finance_read on public.vericlaim_funder_receipt_allocation for select to authenticated
using (exists (
 select 1 from public.vericlaim_funder_receipt r
 join public.practice_staff_member m on m.practice_id=r.practice_id
 where r.id=vericlaim_funder_receipt_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active
   and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy vericlaim_scheme_claim_finance_read on public.vericlaim_scheme_claim_snapshot for select to authenticated
using (exists (
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.practice_id=vericlaim_scheme_claim_snapshot.practice_id and m.active
   and m.role in ('billing','practice_manager','system_admin','auditor')
));
create policy vericlaim_population_staff_read on public.vericlaim_scheme_population_snapshot for select to authenticated
using (exists (
 select 1 from public.practice_staff_member m
 where m.user_id=(select auth.uid()) and m.practice_id=vericlaim_scheme_population_snapshot.practice_id and m.active
));

-- Explicitly deny browser access to raw import-file objects.
drop policy if exists practice_import_files_deny_client on storage.objects;
create policy practice_import_files_deny_client on storage.objects for all to anon,authenticated
using(false) with check(false);

create or replace function public.ensure_vericlaim_patient(
  p_practice_id uuid,
  p_account_ref text,
  p_file_ref text,
  p_display_name text,
  p_source_last_seen_at timestamptz
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare v_patient_id uuid; v_source_ref text;
begin
  if nullif(trim(coalesce(p_account_ref,'')),'') is null then
    return null;
  end if;
  v_source_ref := 'account:' || trim(p_account_ref);

  select id into v_patient_id
  from public.crm_patient
  where practice_id=p_practice_id and source_system='VeriClaim' and source_patient_ref=v_source_ref
  limit 1;

  if v_patient_id is null then
    insert into public.crm_patient(
      practice_id,source_system,source_patient_ref,account_ref,file_ref,
      display_name,status,data_quality_status,source_last_seen_at
    ) values(
      p_practice_id,'VeriClaim',v_source_ref,trim(p_account_ref),nullif(trim(coalesce(p_file_ref,'')),''),
      coalesce(nullif(trim(p_display_name),''),'VeriClaim account '||trim(p_account_ref)),
      'active','source_verified',p_source_last_seen_at
    ) returning id into v_patient_id;
  else
    update public.crm_patient
    set display_name=coalesce(nullif(trim(p_display_name),''),display_name),
        account_ref=coalesce(nullif(trim(p_account_ref),''),account_ref),
        file_ref=coalesce(nullif(trim(coalesce(p_file_ref,'')),''),file_ref),
        data_quality_status=case when data_quality_status='staff_verified' then data_quality_status else 'source_verified' end,
        source_last_seen_at=greatest(coalesce(source_last_seen_at,'epoch'::timestamptz),p_source_last_seen_at),
        updated_at=now()
    where id=v_patient_id;
  end if;
  return v_patient_id;
end;
$$;

revoke all on function public.ensure_vericlaim_patient(uuid,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.ensure_vericlaim_patient(uuid,text,text,text,timestamptz) to service_role;

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
        if nullif(trim(coalesce(r.cell_no,'')),'') is not null then
          if not exists(select 1 from public.crm_contact_point where patient_id=v_patient and contact_type='mobile' and value=r.cell_no) then
            insert into public.crm_contact_point(patient_id,contact_type,value,is_primary,source_system,source_last_seen_at)
            values(v_patient,'mobile',r.cell_no,true,'VeriClaim',coalesce(v_batch.snapshot_at,v_batch.created_at));
            v_contacts:=v_contacts+1;
          end if;
        end if;
        if nullif(trim(coalesce(r.email,'')),'') is not null then
          if not exists(select 1 from public.crm_contact_point where patient_id=v_patient and contact_type='email' and lower(value)=lower(r.email)) then
            insert into public.crm_contact_point(patient_id,contact_type,value,is_primary,source_system,source_last_seen_at)
            values(v_patient,'email',r.email,true,'VeriClaim',coalesce(v_batch.snapshot_at,v_batch.created_at));
            v_contacts:=v_contacts+1;
          end if;
        end if;
      end if;

      insert into public.revenue_account_snapshot(
        practice_id,patient_id,import_batch_id,snapshot_at,patient_name_snapshot,
        account_ref,file_ref,scheme_name_snapshot,days_120_plus,days_90,days_60,days_30,current_amount,total_amount,
        liability_status,collection_suppressed,suppression_reason
      ) values(
        v_batch.practice_id,v_patient,p_import_batch_id,coalesce(v_batch.snapshot_at,v_batch.created_at),r.patient_name,
        r.account_ref,r.file_ref,r.scheme_name,coalesce(r.days_120_plus,0),coalesce(r.days_90,0),coalesce(r.days_60,0),
        coalesce(r.days_30,0),coalesce(r.current_amount,0),coalesce(r.total_amount,0),
        case when coalesce(r.total_amount,0)=0 then 'zero_balance'
             when coalesce(r.total_amount,0)<0 then 'credit' else 'unresolved' end,
        true,
        case when coalesce(r.total_amount,0)<0 then 'Credit balance requires review'
             when coalesce(r.total_amount,0)=0 then 'Zero balance'
             else 'Patient-versus-scheme liability not verified from Age Analysis alone' end
      )
      on conflict(import_batch_id,account_ref,file_ref,patient_name_snapshot) do nothing;
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
    insert into public.vericlaim_funder_receipt(
      practice_id,import_batch_id,receipt_number,medical_scheme,receipt_date,capture_date,receipt_amount
    )
    select v_batch.practice_id,p_import_batch_id,receipt_number,max(medical_scheme),max(receipt_date),max(capture_date),max(coalesce(receipt_amount,0))
    from public.vericlaim_funder_receipts_staging
    where import_batch_id=p_import_batch_id and parse_status='valid' and receipt_number is not null
    group by receipt_number
    on conflict(import_batch_id,receipt_number) do nothing;

    for r in
      select s.*,fr.id receipt_id
      from public.vericlaim_funder_receipts_staging s
      join public.vericlaim_funder_receipt fr
        on fr.import_batch_id=s.import_batch_id and fr.receipt_number=s.receipt_number
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
  else
    raise exception 'Promotion is not implemented for report type %',v_batch.report_type;
  end if;

  update public.vericlaim_import_batch
  set status='promoted',completed_at=now(),
      validation_summary=coalesce(validation_summary,'{}'::jsonb) || jsonb_build_object('promoted_rows',v_count,'contacts_added',v_contacts)
  where id=p_import_batch_id;

  update public.practice_import_file
  set status='promoted'
  where id=v_batch.import_file_id;

  return jsonb_build_object('report_type',v_batch.report_type,'promoted_rows',v_count,'contacts_added',v_contacts);
end;
$$;

revoke all on function public.promote_vericlaim_import(uuid,uuid) from public,anon,authenticated;
grant execute on function public.promote_vericlaim_import(uuid,uuid) to service_role;

commit;
