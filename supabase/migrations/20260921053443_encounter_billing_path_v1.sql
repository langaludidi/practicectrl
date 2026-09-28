
begin;

create table if not exists public.encounter_billing_context (
  encounter_id uuid primary key references public.practice_encounter(id) on delete cascade,
  billing_path text not null default 'unresolved'
    check (billing_path in ('unresolved','private_pay','medical_scheme','no_charge','other')),
  membership_id uuid references public.crm_patient_scheme_membership(id) on delete restrict,
  set_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint encounter_billing_membership_ck check (
    (billing_path='medical_scheme' and membership_id is not null)
    or (billing_path<>'medical_scheme' and membership_id is null)
    or billing_path='unresolved'
  )
);
create index if not exists encounter_billing_context_membership_idx
  on public.encounter_billing_context(membership_id) where membership_id is not null;
create index if not exists encounter_billing_context_set_by_idx
  on public.encounter_billing_context(set_by) where set_by is not null;

create table if not exists public.encounter_billing_context_event (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid not null references public.practice_encounter(id) on delete cascade,
  from_path text,
  to_path text not null,
  from_membership_id uuid,
  to_membership_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists encounter_billing_event_encounter_idx
  on public.encounter_billing_context_event(encounter_id,created_at desc);
create index if not exists encounter_billing_event_actor_idx
  on public.encounter_billing_context_event(actor_user_id) where actor_user_id is not null;

alter table public.encounter_billing_context enable row level security;
alter table public.encounter_billing_context_event enable row level security;

revoke all on table public.encounter_billing_context from anon,authenticated;
revoke all on table public.encounter_billing_context_event from anon,authenticated;
grant select,insert,update on table public.encounter_billing_context to authenticated;
grant select on table public.encounter_billing_context_event to authenticated;

create policy encounter_billing_context_staff_read
on public.encounter_billing_context for select to authenticated
using (exists(
  select 1 from public.practice_encounter e
  join public.practice_staff_member m on m.practice_id=e.practice_id
  where e.id=encounter_billing_context.encounter_id
    and m.user_id=(select auth.uid()) and m.active
));

create policy encounter_billing_context_staff_insert
on public.encounter_billing_context for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and set_by=(select auth.uid())
  and exists(
    select 1 from public.practice_encounter e
    join public.practice_staff_member m on m.practice_id=e.practice_id
    where e.id=encounter_billing_context.encounter_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')
  )
);

create policy encounter_billing_context_staff_update
on public.encounter_billing_context for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(
    select 1 from public.practice_encounter e
    join public.practice_staff_member m on m.practice_id=e.practice_id
    where e.id=encounter_billing_context.encounter_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')
  )
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and set_by=(select auth.uid())
  and exists(
    select 1 from public.practice_encounter e
    join public.practice_staff_member m on m.practice_id=e.practice_id
    where e.id=encounter_billing_context.encounter_id
      and m.user_id=(select auth.uid()) and m.active
      and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')
  )
);

create policy encounter_billing_event_staff_read
on public.encounter_billing_context_event for select to authenticated
using (exists(
  select 1 from public.practice_encounter e
  join public.practice_staff_member m on m.practice_id=e.practice_id
  where e.id=encounter_billing_context_event.encounter_id
    and m.user_id=(select auth.uid()) and m.active
));

create or replace function public.seed_encounter_billing_context()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  insert into public.encounter_billing_context(encounter_id,billing_path,membership_id,set_by)
  values(new.id,'unresolved',null,null)
  on conflict(encounter_id) do nothing;
  return new;
end;
$$;
revoke all on function public.seed_encounter_billing_context() from public,anon,authenticated;

drop trigger if exists trg_seed_encounter_billing_context on public.practice_encounter;
create trigger trg_seed_encounter_billing_context
after insert on public.practice_encounter
for each row execute function public.seed_encounter_billing_context();

insert into public.encounter_billing_context(encounter_id,billing_path,membership_id,set_by)
select id,'unresolved',null,null from public.practice_encounter
on conflict(encounter_id) do nothing;

create or replace function public.audit_encounter_billing_context()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if tg_op='INSERT' then
    if new.set_by is not null then
      insert into public.encounter_billing_context_event(
        encounter_id,from_path,to_path,from_membership_id,to_membership_id,actor_user_id
      ) values(new.encounter_id,null,new.billing_path,null,new.membership_id,coalesce((select auth.uid()),new.set_by));
    end if;
  elsif new.billing_path is distinct from old.billing_path or new.membership_id is distinct from old.membership_id then
    insert into public.encounter_billing_context_event(
      encounter_id,from_path,to_path,from_membership_id,to_membership_id,actor_user_id
    ) values(new.encounter_id,old.billing_path,new.billing_path,old.membership_id,new.membership_id,coalesce((select auth.uid()),new.set_by));
  end if;
  return new;
end;
$$;
revoke all on function public.audit_encounter_billing_context() from public,anon,authenticated;

drop trigger if exists trg_audit_encounter_billing_context on public.encounter_billing_context;
create trigger trg_audit_encounter_billing_context
after insert or update on public.encounter_billing_context
for each row execute function public.audit_encounter_billing_context();

create or replace function public.set_encounter_billing_context(
  p_encounter_id uuid,
  p_billing_path text,
  p_membership_id uuid default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_enc public.practice_encounter%rowtype;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_billing_path not in ('unresolved','private_pay','medical_scheme','no_charge','other') then
    raise exception 'Invalid billing path';
  end if;

  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then raise exception 'Encounter not found or not accessible'; end if;

  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_enc.practice_id and m.active
      and m.role in ('practitioner','reception','billing','practice_manager','clinical_admin','system_admin')
  ) then raise exception 'Encounter billing-context role required'; end if;

  if p_billing_path='medical_scheme' then
    if p_membership_id is null then raise exception 'A patient scheme membership is required'; end if;
    if not exists(
      select 1 from public.crm_patient_scheme_membership m
      where m.id=p_membership_id
        and m.practice_id=v_enc.practice_id
        and m.patient_id=v_enc.patient_id
    ) then raise exception 'Selected membership does not belong to this patient/practice'; end if;
  else
    p_membership_id:=null;
  end if;

  insert into public.encounter_billing_context(encounter_id,billing_path,membership_id,set_by,updated_at)
  values(p_encounter_id,p_billing_path,p_membership_id,v_user,now())
  on conflict(encounter_id) do update set
    billing_path=excluded.billing_path,
    membership_id=excluded.membership_id,
    set_by=excluded.set_by,
    updated_at=now();

  return p_encounter_id;
end;
$$;
revoke all on function public.set_encounter_billing_context(uuid,text,uuid) from public,anon;
grant execute on function public.set_encounter_billing_context(uuid,text,uuid) to authenticated;

create or replace function public.assess_encounter_readiness(p_encounter_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public,pg_temp
as $$
declare
  v_enc public.practice_encounter%rowtype;
  v_completion_missing text[] := '{}';
  v_coding_missing text[] := '{}';
  v_billing_missing text[] := '{}';
  v_mit boolean := false;
  v_ccsa boolean := false;
  v_confirmed integer := 0;
  v_primary integer := 0;
  v_invoices integer := 0;
  v_path text := 'unresolved';
  v_membership uuid;
  v_membership_verified boolean := false;
  v_private_ready boolean := false;
  v_scheme_ready boolean := false;
  v_no_charge_ready boolean := false;
begin
  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then return jsonb_build_object('found',false,'ready',false,'reasons',jsonb_build_array('Encounter not found or not accessible')); end if;

  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=v_enc.practice_id and m.active
  ) then return jsonb_build_object('found',false,'ready',false,'reasons',jsonb_build_array('Active practice membership required')); end if;

  select coalesce(c.billing_path,'unresolved'),c.membership_id
  into v_path,v_membership
  from public.encounter_billing_context c
  where c.encounter_id=v_enc.id;

  if v_membership is not null then
    select membership_status='active_verified'
      and (effective_from is null or effective_from<=v_enc.service_date)
      and (effective_to is null or effective_to>=v_enc.service_date)
    into v_membership_verified
    from public.crm_patient_scheme_membership
    where id=v_membership;
    v_membership_verified:=coalesce(v_membership_verified,false);
  end if;

  select coalesce(array_agg(r.display_name order by r.display_name) filter(where r.required_for_completion and coalesce(s.status,'missing')<>'documented'),'{}'::text[]),
         coalesce(array_agg(r.display_name order by r.display_name) filter(where r.required_for_coding and coalesce(s.status,'missing')<>'documented'),'{}'::text[]),
         coalesce(array_agg(r.display_name order by r.display_name) filter(where r.required_for_billing and coalesce(s.status,'missing')<>'documented'),'{}'::text[])
  into v_completion_missing,v_coding_missing,v_billing_missing
  from public.encounter_documentation_requirement r
  left join public.encounter_documentation_status s
    on s.encounter_id=v_enc.id and s.requirement_key=r.requirement_key
  where r.active and ('all'=any(r.applies_to) or v_enc.encounter_type=any(r.applies_to));

  select exists(
    select 1 from public.coding_source_release
    where authority='NDOH' and source_name='ICD-10 Master Industry Table' and status='active'
  ) into v_mit;

  select exists(
    select 1 from public.billing_code_reference b
    join public.source_dataset_release sr on sr.id=b.source_release_id
    join public.source_dataset d on d.id=sr.dataset_id
    where b.code_system='SAMA_CCSA' and b.active and sr.status='active' and d.licence_required
  ) into v_ccsa;

  select count(*) filter(where d.decision in ('ACCEPTED','MANUALLY_SELECTED')),
         count(*) filter(where d.decision in ('ACCEPTED','MANUALLY_SELECTED') and d.position='primary')
  into v_confirmed,v_primary
  from public.coding_decision d
  join public.coding_session s on s.id=d.coding_session_id
  join public.coding_source_release r on r.id=s.mit_release_id
  where s.encounter_id=v_enc.id and s.status='completed' and r.status='active';

  select count(*) into v_invoices from public.billing_invoice where encounter_id=v_enc.id;

  v_private_ready := v_path in ('private_pay','other')
                     and cardinality(v_billing_missing)=0
                     and v_enc.status='completed';
  v_scheme_ready := v_path='medical_scheme'
                    and cardinality(v_billing_missing)=0
                    and v_enc.status='completed'
                    and v_confirmed>0 and v_primary>0
                    and v_ccsa and v_membership_verified;
  v_no_charge_ready := v_path='no_charge' and v_enc.status='completed';

  return jsonb_build_object(
    'found',true,
    'encounter_id',v_enc.id,
    'encounter_status',v_enc.status,
    'completion',jsonb_build_object(
      'ready',cardinality(v_completion_missing)=0,
      'missing',to_jsonb(v_completion_missing)
    ),
    'coding',jsonb_build_object(
      'documentation_ready',cardinality(v_coding_missing)=0,
      'missing_documentation',to_jsonb(v_coding_missing),
      'authoritative_mit_active',v_mit,
      'confirmed_codes',v_confirmed,
      'confirmed_primary_codes',v_primary,
      'coding_confirmed',v_confirmed>0 and v_primary>0,
      'ready_for_code10',cardinality(v_coding_missing)=0 and v_mit,
      'complete',cardinality(v_coding_missing)=0 and v_mit and v_confirmed>0 and v_primary>0
    ),
    'billing',jsonb_build_object(
      'billing_path',v_path,
      'billing_path_resolved',v_path<>'unresolved',
      'membership_id',v_membership,
      'membership_verified',v_membership_verified,
      'documentation_ready',cardinality(v_billing_missing)=0,
      'missing_documentation',to_jsonb(v_billing_missing),
      'encounter_completed',v_enc.status='completed',
      'coding_confirmed',v_confirmed>0 and v_primary>0,
      'licensed_ccsa_active',v_ccsa,
      'private_billing_ready',v_private_ready,
      'scheme_billing_ready',v_scheme_ready,
      'no_charge_ready',v_no_charge_ready,
      'handoff_ready',v_private_ready or v_scheme_ready or v_no_charge_ready,
      'linked_invoices',v_invoices
    )
  );
end;
$$;

create or replace function public.refresh_encounter_handoff_work(p_encounter_id uuid)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_enc public.practice_encounter%rowtype;
  v_coding_confirmed boolean := false;
  v_ccsa boolean := false;
  v_path text := 'unresolved';
  v_membership uuid;
  v_membership_verified boolean := false;
  v_any_invoice_count integer := 0;
  v_scheme_invoice_count integer := 0;
  v_coding_status text;
  v_billing_status text;
  v_blocked_reason text;
  v_description text;
begin
  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then return; end if;

  select coalesce(c.billing_path,'unresolved'),c.membership_id
  into v_path,v_membership
  from public.encounter_billing_context c
  where c.encounter_id=v_enc.id;

  if v_membership is not null then
    select membership_status='active_verified'
      and (effective_from is null or effective_from<=v_enc.service_date)
      and (effective_to is null or effective_to>=v_enc.service_date)
    into v_membership_verified
    from public.crm_patient_scheme_membership
    where id=v_membership;
    v_membership_verified:=coalesce(v_membership_verified,false);
  end if;

  select exists(
    select 1
    from public.coding_session s
    join public.coding_decision d on d.coding_session_id=s.id
    join public.coding_source_release r on r.id=s.mit_release_id
    where s.encounter_id=v_enc.id
      and s.status='completed'
      and r.status='active'
      and d.position='primary'
      and d.decision in ('ACCEPTED','MANUALLY_SELECTED')
  ) into v_coding_confirmed;

  select exists(
    select 1
    from public.billing_code_reference b
    join public.source_dataset_release sr on sr.id=b.source_release_id
    join public.source_dataset d on d.id=sr.dataset_id
    where b.code_system='SAMA_CCSA' and b.active and sr.status='active' and d.licence_required
  ) into v_ccsa;

  select count(*),count(*) filter(where medical_scheme_id is not null)
  into v_any_invoice_count,v_scheme_invoice_count
  from public.billing_invoice
  where encounter_id=v_enc.id and status<>'voided';

  if v_enc.status='completed' then
    v_coding_status:=case when v_coding_confirmed then 'completed' else 'open' end;
    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,
      title,description,priority,status,due_at,completed_at,created_by
    ) values(
      v_enc.practice_id,v_enc.patient_id,'coding','practice_encounter',v_enc.id,
      'Complete Code10 coding',
      'Completed encounter requires a clinician-confirmed primary Code10 decision.',
      'high',v_coding_status,
      case when v_coding_confirmed then null else now()+interval '1 day' end,
      case when v_coding_confirmed then now() else null end,
      v_enc.created_by
    )
    on conflict(practice_id,source_entity_type,source_entity_id,category)
      where source_entity_id is not null
    do update set status=excluded.status,due_at=excluded.due_at,
      completed_at=excluded.completed_at,blocked_reason=null,
      description=excluded.description,updated_at=now();

    v_blocked_reason:=null;
    if v_path='unresolved' then
      v_billing_status:='blocked';
      v_blocked_reason:='Encounter billing path has not been resolved';
      v_description:='Resolve whether this encounter is private pay, medical scheme, no charge or another billing path.';
    elsif v_path='no_charge' then
      v_billing_status:='completed';
      v_description:='Encounter is marked no charge; no invoice is required.';
    elsif v_path in ('private_pay','other') then
      v_billing_status:=case when v_any_invoice_count>0 then 'completed' else 'open' end;
      v_description:=case when v_any_invoice_count>0 then 'Encounter has a linked PracticeCtrl invoice.' else 'Encounter is ready for controlled non-scheme billing.' end;
    else
      if v_scheme_invoice_count>0 then
        v_billing_status:='completed';
        v_description:='Encounter has a linked scheme invoice.';
      elsif not v_coding_confirmed then
        v_billing_status:='blocked';v_blocked_reason:='Clinician-confirmed primary Code10 coding is incomplete';v_description:='Medical-scheme billing waits for confirmed coding.';
      elsif not v_membership_verified then
        v_billing_status:='blocked';v_blocked_reason:='Selected medical-scheme membership is not active and verified for the service date';v_description:='Medical-scheme billing waits for verified membership.';
      elsif not v_ccsa then
        v_billing_status:='blocked';v_blocked_reason:='Active licensed SAMA CCSA procedure dataset is not available';v_description:='Medical-scheme billing remains externally gated.';
      else
        v_billing_status:='open';v_description:='Coding and membership are confirmed; controlled scheme billing can proceed.';
      end if;
    end if;

    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,
      title,description,priority,status,due_at,blocked_reason,completed_at,created_by
    ) values(
      v_enc.practice_id,v_enc.patient_id,'billing','practice_encounter',v_enc.id,
      'Complete encounter billing',v_description,'high',v_billing_status,
      case when v_billing_status='open' then now()+interval '1 day' else null end,
      v_blocked_reason,
      case when v_billing_status='completed' then now() else null end,
      v_enc.created_by
    )
    on conflict(practice_id,source_entity_type,source_entity_id,category)
      where source_entity_id is not null
    do update set status=excluded.status,due_at=excluded.due_at,
      blocked_reason=excluded.blocked_reason,completed_at=excluded.completed_at,
      description=excluded.description,updated_at=now();
  else
    update public.operations_work_item
    set status='cancelled',completed_at=null,updated_at=now()
    where practice_id=v_enc.practice_id
      and source_entity_type='practice_encounter'
      and source_entity_id=v_enc.id
      and category in ('coding','billing')
      and status not in ('completed','cancelled');
  end if;
end;
$$;
revoke all on function public.refresh_encounter_handoff_work(uuid) from public,anon,authenticated;

create or replace function public.trg_refresh_encounter_handoff_from_billing_context()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  perform public.refresh_encounter_handoff_work(new.encounter_id);
  return new;
end;
$$;
revoke all on function public.trg_refresh_encounter_handoff_from_billing_context() from public,anon,authenticated;

drop trigger if exists trg_refresh_encounter_handoff_billing_context on public.encounter_billing_context;
create trigger trg_refresh_encounter_handoff_billing_context
after insert or update of billing_path,membership_id on public.encounter_billing_context
for each row execute function public.trg_refresh_encounter_handoff_from_billing_context();

create or replace function public.create_encounter_private_invoice(
  p_encounter_id uuid,
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
  v_enc public.practice_encounter%rowtype;
  v_path text;
  v_invoice_id uuid := gen_random_uuid();
  v_invoice_number text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
  if length(trim(coalesce(p_description,'')))<2 then raise exception 'Description is required'; end if;

  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then raise exception 'Encounter not found or not accessible'; end if;
  if v_enc.status<>'completed' then raise exception 'Encounter must be completed before private invoicing'; end if;
  if not exists(
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=v_enc.practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  select billing_path into v_path from public.encounter_billing_context where encounter_id=v_enc.id;
  if coalesce(v_path,'unresolved') not in ('private_pay','other') then
    raise exception 'Encounter billing path must be private_pay or other for a custom non-claimable invoice';
  end if;

  if exists(select 1 from public.billing_invoice where encounter_id=v_enc.id and status<>'voided') then
    raise exception 'Encounter already has an active PracticeCtrl invoice';
  end if;

  v_invoice_number:='PCD-'||to_char(v_enc.service_date,'YYYYMMDD')||'-'||upper(substr(replace(v_invoice_id::text,'-',''),1,8));

  insert into public.billing_invoice(
    id,practice_id,patient_id,encounter_id,invoice_number,invoice_date,status,total_amount,
    scheme_portion,patient_portion,received_amount,balance_amount,source_system,created_by
  ) values(
    v_invoice_id,v_enc.practice_id,v_enc.patient_id,v_enc.id,v_invoice_number,v_enc.service_date,
    'draft',p_amount,0,p_amount,0,p_amount,'PracticeCtrl',v_user
  );

  insert into public.billing_invoice_line(
    invoice_id,line_no,code_system,code,description_snapshot,quantity,unit_amount,line_amount,metadata
  ) values(
    v_invoice_id,1,'PRACTICE_CUSTOM','CUSTOM',trim(p_description),1,p_amount,p_amount,
    jsonb_build_object('claim_eligible',false,'source','PracticeCtrl encounter private billing')
  );

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(v_invoice_id,'created',v_user,jsonb_build_object(
    'encounter_id',v_enc.id,'invoice_number',v_invoice_number,'custom_draft',true,'billing_path',v_path
  ));

  return v_invoice_id;
end;
$$;
revoke all on function public.create_encounter_private_invoice(uuid,text,numeric) from public,anon;
grant execute on function public.create_encounter_private_invoice(uuid,text,numeric) to authenticated;

commit;
