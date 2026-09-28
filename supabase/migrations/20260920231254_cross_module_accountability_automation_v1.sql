
begin;

create unique index if not exists operations_work_source_uq
  on public.operations_work_item(practice_id,source_entity_type,source_entity_id,category)
  where source_entity_id is not null;

create or replace function public.pc_due_at(
  p_practice_id uuid,
  p_category text,
  p_priority text,
  p_fallback_minutes integer
)
returns timestamptz
language sql
stable
security invoker
set search_path=public,pg_temp
as $$
  select now() + make_interval(mins => coalesce(
    (select target_minutes
     from public.operations_sla_policy
     where practice_id=p_practice_id
       and category=p_category
       and priority=p_priority
       and active
     limit 1),
    p_fallback_minutes
  ));
$$;

revoke all on function public.pc_due_at(uuid,text,text,integer) from public,anon;
grant execute on function public.pc_due_at(uuid,text,text,integer) to authenticated,service_role;

create or replace function public.sync_appointment_request_work_item()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare v_status text; v_priority text := 'normal'; v_due timestamptz;
begin
  if new.status in ('New','Contacted','Alternative Offered','Unable to Reach') then
    v_status := case
      when new.status='New' then 'open'
      when new.status='Contacted' then 'in_progress'
      else 'waiting'
    end;
    v_due := public.pc_due_at(new.practice_id,'appointment_request',v_priority,1440);
    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,
      title,description,priority,status,owner_user_id,due_at,created_by
    ) values(
      new.practice_id,new.patient_id,'appointment_request','appointment_request',new.id,
      'Appointment request: ' || new.requester_name,
      coalesce(new.requested_service,'Contact patient and progress appointment request.'),
      v_priority,v_status,new.assigned_to,v_due,new.created_by
    )
    on conflict (practice_id,source_entity_type,source_entity_id,category)
      where source_entity_id is not null
    do update set
      patient_id=excluded.patient_id,
      status=excluded.status,
      owner_user_id=coalesce(excluded.owner_user_id,public.operations_work_item.owner_user_id),
      due_at=case when public.operations_work_item.status in ('completed','cancelled')
                  then excluded.due_at else public.operations_work_item.due_at end,
      updated_at=now();
  else
    update public.operations_work_item
    set status=case when new.status='Duplicate' then 'cancelled' else 'completed' end,
        completed_at=case when new.status='Duplicate' then completed_at else coalesce(completed_at,now()) end,
        updated_at=now()
    where practice_id=new.practice_id
      and source_entity_type='appointment_request'
      and source_entity_id=new.id
      and category='appointment_request'
      and status not in ('completed','cancelled');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_appointment_request_work_item on public.appointment_request;
create trigger trg_sync_appointment_request_work_item
after insert or update of status,assigned_to,patient_id on public.appointment_request
for each row execute function public.sync_appointment_request_work_item();

create or replace function public.sync_claim_exception_work_item()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare v_due timestamptz;
begin
  if new.claim_status in ('rejected','exception','partially_accepted') then
    v_due := public.pc_due_at(new.practice_id,'claim','high',1440);
    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,
      title,description,priority,status,due_at,created_by
    ) values(
      new.practice_id,new.patient_id,'claim','claim_record',new.id,
      'Claim requires attention',
      'Review claim status ' || new.claim_status || coalesce(' · tracking ' || new.latest_tracking_number,''),
      'high','open',v_due,new.created_by
    )
    on conflict (practice_id,source_entity_type,source_entity_id,category)
      where source_entity_id is not null
    do update set
      patient_id=excluded.patient_id,
      description=excluded.description,
      status=case when public.operations_work_item.status='completed' then 'open' else public.operations_work_item.status end,
      due_at=case when public.operations_work_item.status='completed' then excluded.due_at else public.operations_work_item.due_at end,
      completed_at=null,
      updated_at=now();
  elsif tg_op='UPDATE' and old.claim_status in ('rejected','exception','partially_accepted') then
    update public.operations_work_item
    set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
    where practice_id=new.practice_id
      and source_entity_type='claim_record' and source_entity_id=new.id and category='claim'
      and status not in ('completed','cancelled');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_claim_exception_work_item on public.claim_record;
create trigger trg_sync_claim_exception_work_item
after insert or update of claim_status,latest_tracking_number on public.claim_record
for each row execute function public.sync_claim_exception_work_item();

create or replace function public.sync_revenue_case_work_item()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare v_due timestamptz; v_work_status text;
begin
  if new.case_status in ('review_required','ready_for_contact','contacted','arrangement','waiting_scheme','external_recovery') then
    v_due := public.pc_due_at(new.practice_id,'revenue','high',1440);
    v_work_status := case
      when new.case_status in ('waiting_scheme','external_recovery') then 'waiting'
      when new.suppress_automation then 'blocked'
      else 'open'
    end;
    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,
      title,description,priority,status,owner_user_id,due_at,blocked_reason,created_by
    ) values(
      new.practice_id,new.patient_id,'revenue','revenue_collection_case',new.id,
      'Revenue case requires action',
      coalesce('Account ' || new.account_ref || ' · ','') || 'Liability: ' || new.liability_status,
      'high',v_work_status,new.owner_user_id,v_due,
      case when new.suppress_automation then coalesce(new.suppression_reason,'Automation suppressed pending review') end,
      new.created_by
    )
    on conflict (practice_id,source_entity_type,source_entity_id,category)
      where source_entity_id is not null
    do update set
      patient_id=excluded.patient_id,
      status=excluded.status,
      owner_user_id=coalesce(excluded.owner_user_id,public.operations_work_item.owner_user_id),
      blocked_reason=excluded.blocked_reason,
      description=excluded.description,
      updated_at=now();
  else
    update public.operations_work_item
    set status=case when new.case_status='suppressed' then 'blocked' else 'completed' end,
        blocked_reason=case when new.case_status='suppressed' then coalesce(new.suppression_reason,'Revenue case suppressed') else null end,
        completed_at=case when new.case_status in ('resolved','closed') then coalesce(completed_at,now()) else completed_at end,
        updated_at=now()
    where practice_id=new.practice_id
      and source_entity_type='revenue_collection_case' and source_entity_id=new.id and category='revenue';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_revenue_case_work_item on public.revenue_collection_case;
create trigger trg_sync_revenue_case_work_item
after insert or update of case_status,owner_user_id,suppress_automation,suppression_reason,liability_status
on public.revenue_collection_case
for each row execute function public.sync_revenue_case_work_item();

create or replace function public.sync_validation_work_item()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare v_practice uuid; v_patient uuid; v_category text; v_source_type text; v_title text;
begin
  if tg_table_name='billing_validation_event' then
    select i.practice_id,i.patient_id into v_practice,v_patient
    from public.billing_invoice i where i.id=new.invoice_id;
    v_category:='billing'; v_source_type:='billing_validation_event'; v_title:='Blocking billing validation';
  else
    v_practice:=new.practice_id;
    select s.patient_id into v_patient from public.coding_session s where s.id=new.coding_session_id;
    v_category:='coding'; v_source_type:='coding_validation_event'; v_title:='Blocking Code10 validation';
  end if;

  if new.severity in ('blocking','BLOCKING') and new.status in ('open','acknowledged') then
    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,
      title,description,priority,status,due_at,created_by
    ) values(
      v_practice,v_patient,v_category,v_source_type,new.id,
      v_title,new.message,'high','open',
      public.pc_due_at(v_practice,case when v_category='coding' then 'documentation' else 'billing' end,'high',480),
      coalesce(new.actor_user_id,null)
    )
    on conflict (practice_id,source_entity_type,source_entity_id,category)
      where source_entity_id is not null
    do update set status='open',description=excluded.description,completed_at=null,updated_at=now();
  else
    update public.operations_work_item
    set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
    where practice_id=v_practice and source_entity_type=v_source_type
      and source_entity_id=new.id and category=v_category and status not in ('completed','cancelled');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_billing_validation_work_item on public.billing_validation_event;
create trigger trg_sync_billing_validation_work_item
after insert or update of severity,status,message on public.billing_validation_event
for each row execute function public.sync_validation_work_item();

drop trigger if exists trg_sync_coding_validation_work_item on public.coding_validation_event;
create trigger trg_sync_coding_validation_work_item
after insert or update of severity,status,message on public.coding_validation_event
for each row execute function public.sync_validation_work_item();

create or replace function public.sync_failed_communication_work_item()
returns trigger
language plpgsql
security invoker
set search_path=public,pg_temp
as $$
declare v_practice uuid; v_patient uuid;
begin
  select t.practice_id,t.patient_id into v_practice,v_patient
  from public.communication_thread t where t.id=new.thread_id;
  if new.status='failed' then
    insert into public.operations_work_item(
      practice_id,patient_id,category,source_entity_type,source_entity_id,
      title,description,priority,status,due_at,created_by
    ) values(
      v_practice,v_patient,'communication','communication_message',new.id,
      'Communication delivery failed',
      'Review failed ' || new.channel || ' message and select a safe fallback route.',
      'high','open',now()+interval '4 hours',new.created_by
    )
    on conflict (practice_id,source_entity_type,source_entity_id,category)
      where source_entity_id is not null
    do update set status='open',completed_at=null,updated_at=now();
  elsif tg_op='UPDATE' and old.status='failed' and new.status in ('sent','delivered','received','cancelled') then
    update public.operations_work_item
    set status=case when new.status='cancelled' then 'cancelled' else 'completed' end,
        completed_at=case when new.status<>'cancelled' then coalesce(completed_at,now()) else completed_at end,
        updated_at=now()
    where practice_id=v_practice and source_entity_type='communication_message'
      and source_entity_id=new.id and category='communication';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_failed_communication_work_item on public.communication_message;
create trigger trg_sync_failed_communication_work_item
after insert or update of status on public.communication_message
for each row execute function public.sync_failed_communication_work_item();

-- Lightweight patient timeline automation; never copies message bodies or clinical narrative.
create or replace function public.pc_timeline_from_invoice()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if new.patient_id is not null then
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system)
  values(new.practice_id,new.patient_id,'invoice',new.created_at,'Invoice '||new.invoice_number,
    'Status '||new.status||' · balance R'||to_char(new.balance_amount,'FM999999990.00'),
    'billing_invoice',new.id,new.created_by,new.source_system);
 end if;
 return new;
end; $$;
drop trigger if exists trg_timeline_invoice on public.billing_invoice;
create trigger trg_timeline_invoice after insert on public.billing_invoice
for each row execute function public.pc_timeline_from_invoice();

create or replace function public.pc_timeline_from_claim()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if new.patient_id is not null then
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system)
  values(new.practice_id,new.patient_id,'claim',new.created_at,'Claim created',
    'Status '||new.claim_status||' · claimed R'||to_char(new.total_claimed,'FM999999990.00'),
    'claim_record',new.id,new.created_by,'PracticeCtrl');
 end if;
 return new;
end; $$;
drop trigger if exists trg_timeline_claim on public.claim_record;
create trigger trg_timeline_claim after insert on public.claim_record
for each row execute function public.pc_timeline_from_claim();

create or replace function public.pc_timeline_from_communication()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_practice uuid; v_patient uuid;
begin
 select t.practice_id,t.patient_id into v_practice,v_patient from public.communication_thread t where t.id=new.thread_id;
 if v_patient is not null then
  insert into public.crm_timeline_event(practice_id,patient_id,event_type,event_at,title,summary,entity_type,entity_id,actor_user_id,source_system)
  values(v_practice,v_patient,'communication',new.created_at,
    upper(left(new.channel,1))||substr(new.channel,2)||' communication',
    new.direction||' · '||new.status||case when new.contains_clinical_detail then ' · clinical detail flagged' else '' end,
    'communication_message',new.id,new.created_by,'PracticeCtrl');
 end if;
 return new;
end; $$;
drop trigger if exists trg_timeline_communication on public.communication_message;
create trigger trg_timeline_communication after insert on public.communication_message
for each row execute function public.pc_timeline_from_communication();

insert into public.assist_capability(
  capability_key,display_name,capability_type,module_key,description,
  maximum_data_class,requires_human_review,enabled_at_platform
) values
('communications.assistant','Communications assistant','ai','communications',
 'Future drafting, summarisation and channel assistance. No autonomous sending.','health_special',true,false),
('operations.assistant','Operations assistant','ai','operations',
 'Future work-queue prioritisation and summarisation. Cannot silently change ownership or status.','health_special',true,false),
('analytics.assistant','Analytics assistant','ai','analytics',
 'Future natural-language analysis over authorised aggregated PracticeCtrl metrics.','health_special',true,false)
on conflict(capability_key) do update set
 display_name=excluded.display_name,description=excluded.description,maximum_data_class=excluded.maximum_data_class,
 requires_human_review=excluded.requires_human_review,enabled_at_platform=excluded.enabled_at_platform,updated_at=now();

commit;
