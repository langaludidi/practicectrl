
begin;

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
  v_invoice_count integer := 0;
  v_coding_status text;
  v_billing_status text;
begin
  select * into v_enc from public.practice_encounter where id=p_encounter_id;
  if not found then return; end if;

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
    where b.code_system='SAMA_CCSA'
      and b.active and sr.status='active' and d.licence_required
  ) into v_ccsa;

  select count(*) into v_invoice_count
  from public.billing_invoice
  where encounter_id=v_enc.id and status<>'voided';

  if v_enc.status='completed' then
    v_coding_status := case when v_coding_confirmed then 'completed' else 'open' end;

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
    do update set
      status=excluded.status,
      due_at=excluded.due_at,
      completed_at=excluded.completed_at,
      blocked_reason=null,
      description=excluded.description,
      updated_at=now();

    if v_coding_confirmed then
      v_billing_status := case
        when v_invoice_count>0 then 'completed'
        when v_ccsa then 'open'
        else 'blocked'
      end;

      insert into public.operations_work_item(
        practice_id,patient_id,category,source_entity_type,source_entity_id,
        title,description,priority,status,due_at,blocked_reason,completed_at,created_by
      ) values(
        v_enc.practice_id,v_enc.patient_id,'billing','practice_encounter',v_enc.id,
        'Complete encounter billing',
        case when v_invoice_count>0
             then 'Encounter has a linked PracticeCtrl invoice.'
             when v_ccsa
             then 'Coding is confirmed and the encounter is ready for controlled billing work.'
             else 'Coding is confirmed, but scheme-billing data remains externally gated.' end,
        'high',v_billing_status,
        case when v_billing_status='open' then now()+interval '1 day' else null end,
        case when v_billing_status='blocked' then 'Active licensed SAMA CCSA procedure dataset is not available' else null end,
        case when v_billing_status='completed' then now() else null end,
        v_enc.created_by
      )
      on conflict(practice_id,source_entity_type,source_entity_id,category)
        where source_entity_id is not null
      do update set
        status=excluded.status,
        due_at=excluded.due_at,
        blocked_reason=excluded.blocked_reason,
        completed_at=excluded.completed_at,
        description=excluded.description,
        updated_at=now();
    else
      update public.operations_work_item
      set status='cancelled',completed_at=null,updated_at=now()
      where practice_id=v_enc.practice_id
        and category='billing'
        and source_entity_type='practice_encounter'
        and source_entity_id=v_enc.id
        and status not in ('completed','cancelled');
    end if;
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

create or replace function public.trg_refresh_encounter_handoff_from_encounter()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  perform public.refresh_encounter_handoff_work(new.id);
  return new;
end;
$$;
revoke all on function public.trg_refresh_encounter_handoff_from_encounter() from public,anon,authenticated;

drop trigger if exists trg_refresh_encounter_handoff_from_encounter on public.practice_encounter;
create trigger trg_refresh_encounter_handoff_from_encounter
after insert or update of status on public.practice_encounter
for each row execute function public.trg_refresh_encounter_handoff_from_encounter();

create or replace function public.trg_refresh_encounter_handoff_from_coding()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_encounter uuid;
begin
  if tg_table_name='coding_session' then
    v_encounter:=new.encounter_id;
  else
    select encounter_id into v_encounter from public.coding_session where id=new.coding_session_id;
  end if;
  if v_encounter is not null then perform public.refresh_encounter_handoff_work(v_encounter); end if;
  return new;
end;
$$;
revoke all on function public.trg_refresh_encounter_handoff_from_coding() from public,anon,authenticated;

drop trigger if exists trg_refresh_encounter_handoff_session on public.coding_session;
create trigger trg_refresh_encounter_handoff_session
after insert or update of status on public.coding_session
for each row execute function public.trg_refresh_encounter_handoff_from_coding();

drop trigger if exists trg_refresh_encounter_handoff_decision on public.coding_decision;
create trigger trg_refresh_encounter_handoff_decision
after insert on public.coding_decision
for each row execute function public.trg_refresh_encounter_handoff_from_coding();

create or replace function public.trg_refresh_encounter_handoff_from_invoice()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  if new.encounter_id is not null then perform public.refresh_encounter_handoff_work(new.encounter_id); end if;
  if tg_op='UPDATE' and old.encounter_id is distinct from new.encounter_id and old.encounter_id is not null then
    perform public.refresh_encounter_handoff_work(old.encounter_id);
  end if;
  return new;
end;
$$;
revoke all on function public.trg_refresh_encounter_handoff_from_invoice() from public,anon,authenticated;

drop trigger if exists trg_refresh_encounter_handoff_invoice on public.billing_invoice;
create trigger trg_refresh_encounter_handoff_invoice
after insert or update of encounter_id,status on public.billing_invoice
for each row execute function public.trg_refresh_encounter_handoff_from_invoice();

commit;
