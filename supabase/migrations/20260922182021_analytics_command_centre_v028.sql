create or replace function public.get_practicectrl_command_centre(
  p_practice_id uuid,
  p_window_days integer default 30
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_role text;
  v_days integer := greatest(7, least(coalesce(p_window_days, 30), 365));
  v_start_date date := current_date - (greatest(7, least(coalesce(p_window_days, 30), 365)) - 1);
  v_start_ts timestamptz := date_trunc('day', now()) - make_interval(days => greatest(7, least(coalesce(p_window_days, 30), 365)) - 1);
  v_finance boolean := false;
  v_operations jsonb;
  v_patient_flow jsonb;
  v_coding jsonb;
  v_authorisations jsonb;
  v_workload jsonb;
  v_work_categories jsonb;
  v_revenue jsonb := null;
  v_claims jsonb := null;
  v_scheme_exposure jsonb := '[]'::jsonb;
  v_freshness jsonb := '[]'::jsonb;
  v_series jsonb;
begin
  if v_user is null then raise exception 'Authentication required'; end if;

  select m.role::text into v_role
  from public.practice_staff_member m
  where m.practice_id=p_practice_id and m.user_id=v_user and m.active
  limit 1;

  if v_role is null then raise exception 'Active PracticeCtrl membership required'; end if;
  v_finance := v_role in ('billing','practice_manager','system_admin','auditor');

  select jsonb_build_object(
    'active_patients',(select count(*) from public.crm_patient p where p.practice_id=p_practice_id and p.status='active'),
    'new_patients',(select count(*) from public.crm_patient p where p.practice_id=p_practice_id and p.created_at>=v_start_ts),
    'appointments_today',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=date_trunc('day',now()) and a.starts_at<date_trunc('day',now())+interval '1 day' and a.status<>'cancelled'),
    'appointments_window',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=v_start_ts and a.starts_at<date_trunc('day',now())+interval '1 day'),
    'appointments_completed',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=v_start_ts and a.status='completed'),
    'appointments_no_show',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=v_start_ts and a.status='no_show'),
    'appointments_cancelled',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=v_start_ts and a.status='cancelled'),
    'appointments_upcoming_7d',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=now() and a.starts_at<now()+interval '7 days' and a.status in ('booked','confirmed')),
    'encounters_completed',(select count(*) from public.practice_encounter e where e.practice_id=p_practice_id and e.service_date>=v_start_date and e.status='completed'),
    'intake_pending_review',(select count(*) from public.patient_intake_session i where i.practice_id=p_practice_id and i.status in ('submitted','validation_required','under_review')),
    'communications_open',(select count(*) from public.communication_thread t where t.practice_id=p_practice_id and t.status<>'closed'),
    'work_open',(select count(*) from public.operations_work_item w where w.practice_id=p_practice_id and w.status in ('open','in_progress','waiting','blocked')),
    'work_overdue',(select count(*) from public.operations_work_item w where w.practice_id=p_practice_id and w.status in ('open','in_progress','waiting','blocked') and w.due_at<now()),
    'work_blocked',(select count(*) from public.operations_work_item w where w.practice_id=p_practice_id and w.status='blocked'),
    'work_unassigned',(select count(*) from public.operations_work_item w where w.practice_id=p_practice_id and w.status in ('open','in_progress','waiting','blocked') and w.owner_user_id is null)
  ) into v_operations;

  select jsonb_build_object(
    'registered',(select count(*) from public.crm_patient p where p.practice_id=p_practice_id and p.created_at>=v_start_ts),
    'intakes_submitted',(select count(*) from public.patient_intake_session i where i.practice_id=p_practice_id and i.submitted_at>=v_start_ts),
    'intakes_applied',(select count(*) from public.patient_intake_session i where i.practice_id=p_practice_id and i.applied_at>=v_start_ts),
    'encounters',(select count(*) from public.practice_encounter e where e.practice_id=p_practice_id and e.service_date>=v_start_date),
    'completed_encounters',(select count(*) from public.practice_encounter e where e.practice_id=p_practice_id and e.service_date>=v_start_date and e.status='completed')
  ) into v_patient_flow;

  select jsonb_build_object(
    'sessions',(select count(*) from public.coding_session s where s.practice_id=p_practice_id and s.started_at>=v_start_ts),
    'completed_sessions',(select count(*) from public.coding_session s where s.practice_id=p_practice_id and s.started_at>=v_start_ts and s.status='completed'),
    'confirmed_decisions',(select count(*) from public.coding_decision d where d.practice_id=p_practice_id and d.selected_at>=v_start_ts and d.decision in ('ACCEPTED','MANUALLY_SELECTED')),
    'blocking_open',(select count(*) from public.coding_validation_event e where e.practice_id=p_practice_id and e.status in ('open','acknowledged') and e.severity='BLOCKING'),
    'warnings_open',(select count(*) from public.coding_validation_event e where e.practice_id=p_practice_id and e.status in ('open','acknowledged') and e.severity='WARNING'),
    'active_authority_codes',(select count(*) from public.sa_icd10_code c join public.coding_source_release r on r.id=c.source_release_id where r.status='active' and r.authority='NDOH')
  ) into v_coding;

  select jsonb_build_object(
    'requested',(select count(*) from public.scheme_authorisation a where a.practice_id=p_practice_id and a.created_at>=v_start_ts and a.status in ('requested','pending','approved','partially_approved','declined')),
    'pending',(select count(*) from public.scheme_authorisation a where a.practice_id=p_practice_id and a.status in ('requested','pending')),
    'approved',(select count(*) from public.scheme_authorisation a where a.practice_id=p_practice_id and a.created_at>=v_start_ts and a.status in ('approved','partially_approved')),
    'declined',(select count(*) from public.scheme_authorisation a where a.practice_id=p_practice_id and a.created_at>=v_start_ts and a.status='declined'),
    'approval_rate_pct',(
      select case when count(*) filter (where a.status in ('approved','partially_approved','declined'))=0 then null
      else round(100.0*count(*) filter (where a.status in ('approved','partially_approved'))/count(*) filter (where a.status in ('approved','partially_approved','declined')),1) end
      from public.scheme_authorisation a where a.practice_id=p_practice_id and a.created_at>=v_start_ts
    )
  ) into v_authorisations;

  select coalesce(jsonb_agg(q.item order by q.open_count desc,q.overdue_count desc,q.email),'[]'::jsonb)
  into v_workload
  from (
    select jsonb_build_object(
      'user_id',m.user_id,'email',coalesce(m.email,'Staff member'),'role',m.role::text,
      'open_count',count(w.id) filter (where w.status in ('open','in_progress','waiting','blocked')),
      'overdue_count',count(w.id) filter (where w.status in ('open','in_progress','waiting','blocked') and w.due_at<now()),
      'blocked_count',count(w.id) filter (where w.status='blocked')
    ) item,coalesce(m.email,'Staff member') email,
    count(w.id) filter (where w.status in ('open','in_progress','waiting','blocked')) open_count,
    count(w.id) filter (where w.status in ('open','in_progress','waiting','blocked') and w.due_at<now()) overdue_count
    from public.practice_staff_member m
    left join public.operations_work_item w on w.practice_id=m.practice_id and w.owner_user_id=m.user_id
    where m.practice_id=p_practice_id and m.active
    group by m.user_id,m.email,m.role
    union all
    select jsonb_build_object(
      'user_id',null,'email','Unassigned','role','unassigned','open_count',count(*),
      'overdue_count',count(*) filter (where due_at<now()),'blocked_count',count(*) filter (where status='blocked')
    ) item,'Unassigned',count(*),count(*) filter (where due_at<now())
    from public.operations_work_item
    where practice_id=p_practice_id and owner_user_id is null and status in ('open','in_progress','waiting','blocked')
    having count(*)>0
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object('category',category,'count',cnt,'overdue',overdue) order by cnt desc,category),'[]'::jsonb)
  into v_work_categories
  from (
    select category,count(*) cnt,count(*) filter (where due_at<now()) overdue
    from public.operations_work_item
    where practice_id=p_practice_id and status in ('open','in_progress','waiting','blocked')
    group by category
  ) x;

  if v_finance then
    select jsonb_build_object(
      'invoices',count(*),'billed',coalesce(sum(i.total_amount),0),'received',coalesce(sum(i.received_amount),0),
      'outstanding',coalesce(sum(i.balance_amount),0),
      'collection_rate_pct',case when coalesce(sum(i.total_amount),0)=0 then null else round(100.0*sum(i.received_amount)/nullif(sum(i.total_amount),0),1) end,
      'overdue_balance',coalesce((select sum(x.balance_amount) from public.billing_invoice x where x.practice_id=p_practice_id and x.status in ('final','part_paid','outstanding') and x.balance_amount>0 and x.due_date<current_date),0),
      'actionable_collection_cases',(select count(*) from public.revenue_collection_case c where c.practice_id=p_practice_id and c.case_status in ('review_required','ready_for_contact','contacted','arrangement','waiting_scheme','external_recovery')),
      'collection_case_exposure',coalesce((select sum(c.balance_snapshot) from public.revenue_collection_case c where c.practice_id=p_practice_id and c.case_status in ('review_required','ready_for_contact','contacted','arrangement','waiting_scheme','external_recovery')),0),
      'open_variances',(select count(*) from public.payer_remittance_variance v where v.practice_id=p_practice_id and v.status in ('unreviewed','disputed')),
      'variance_exposure',coalesce((select sum(abs(v.variance_amount)) from public.payer_remittance_variance v where v.practice_id=p_practice_id and v.status in ('unreviewed','disputed')),0)
    ) into v_revenue
    from public.billing_invoice i
    where i.practice_id=p_practice_id and i.invoice_date>=v_start_date and i.status<>'void';

    select jsonb_build_object(
      'claims',count(*),
      'submitted',count(*) filter (where c.claim_status in ('submitted','accepted','partially_accepted','rejected','paid','part_paid','exception')),
      'accepted',count(*) filter (where c.claim_status in ('accepted','paid')),
      'partially_accepted',count(*) filter (where c.claim_status in ('partially_accepted','part_paid')),
      'rejected',count(*) filter (where c.claim_status='rejected'),
      'exceptions',count(*) filter (where c.claim_status='exception'),
      'total_claimed',coalesce(sum(c.total_claimed),0),'total_paid',coalesce(sum(c.total_paid),0),
      'paid_ratio_pct',case when coalesce(sum(c.total_claimed),0)=0 then null else round(100.0*sum(c.total_paid)/nullif(sum(c.total_claimed),0),1) end,
      'clean_acceptance_pct',case when count(*) filter (where c.claim_status in ('accepted','partially_accepted','rejected','paid','part_paid','exception'))=0 then null
      else round(100.0*count(*) filter (where c.claim_status in ('accepted','paid'))/count(*) filter (where c.claim_status in ('accepted','partially_accepted','rejected','paid','part_paid','exception')),1) end
    ) into v_claims
    from public.claim_record c
    where c.practice_id=p_practice_id and coalesce(c.submitted_at,c.created_at)>=v_start_ts and c.claim_status<>'cancelled';

    select coalesce(jsonb_agg(jsonb_build_object(
      'scheme_name',scheme_name,'invoice_balance',invoice_balance,'claimed',claimed,'paid',paid,'claim_count',claim_count
    ) order by invoice_balance desc,claimed desc,scheme_name),'[]'::jsonb)
    into v_scheme_exposure
    from (
      select coalesce(ms.name,'Private / self-pay') scheme_name,
        coalesce(sum(i.balance_amount),0) invoice_balance,
        coalesce((select sum(c.total_claimed) from public.claim_record c where c.practice_id=p_practice_id and c.medical_scheme_id is not distinct from i.medical_scheme_id and coalesce(c.submitted_at,c.created_at)>=v_start_ts),0) claimed,
        coalesce((select sum(c.total_paid) from public.claim_record c where c.practice_id=p_practice_id and c.medical_scheme_id is not distinct from i.medical_scheme_id and coalesce(c.submitted_at,c.created_at)>=v_start_ts),0) paid,
        (select count(*) from public.claim_record c where c.practice_id=p_practice_id and c.medical_scheme_id is not distinct from i.medical_scheme_id and coalesce(c.submitted_at,c.created_at)>=v_start_ts) claim_count
      from public.billing_invoice i
      left join public.medical_scheme ms on ms.id=i.medical_scheme_id
      where i.practice_id=p_practice_id and i.status in ('final','part_paid','outstanding') and i.balance_amount>0
      group by i.medical_scheme_id,ms.name
      order by invoice_balance desc
      limit 10
    ) x;

    select coalesce(jsonb_agg(jsonb_build_object(
      'report_type',report_type,'status',status,'row_count',row_count,'rejected_row_count',rejected_row_count,
      'period_start',period_start,'period_end',period_end,'snapshot_at',snapshot_at,'created_at',created_at
    ) order by created_at desc),'[]'::jsonb)
    into v_freshness
    from (
      select distinct on (report_type) report_type,status,row_count,rejected_row_count,period_start,period_end,snapshot_at,created_at
      from public.vericlaim_import_batch
      where practice_id=p_practice_id
      order by report_type,created_at desc
    ) x;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date',d::date,
    'appointments',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=d and a.starts_at<d+interval '1 day' and a.status<>'cancelled'),
    'completed_appointments',(select count(*) from public.practice_appointment a where a.practice_id=p_practice_id and a.starts_at>=d and a.starts_at<d+interval '1 day' and a.status='completed'),
    'encounters',(select count(*) from public.practice_encounter e where e.practice_id=p_practice_id and e.service_date=d::date and e.status<>'cancelled'),
    'new_patients',(select count(*) from public.crm_patient p where p.practice_id=p_practice_id and p.created_at>=d and p.created_at<d+interval '1 day')
  ) order by d),'[]'::jsonb)
  into v_series
  from generate_series(v_start_date::timestamp,current_date::timestamp,interval '1 day') d;

  return jsonb_build_object(
    'generated_at',now(),'window_days',v_days,'window_start',v_start_date,'role',v_role,'finance_allowed',v_finance,
    'operations',v_operations,'patient_flow',v_patient_flow,'coding',v_coding,'authorisations',v_authorisations,
    'workload',v_workload,'work_categories',v_work_categories,'revenue',v_revenue,'claims',v_claims,
    'scheme_exposure',v_scheme_exposure,'source_freshness',v_freshness,'patient_flow_series',v_series
  );
end;
$$;

revoke all on function public.get_practicectrl_command_centre(uuid,integer) from public,anon;
grant execute on function public.get_practicectrl_command_centre(uuid,integer) to authenticated;

create index if not exists crm_patient_practice_created_idx on public.crm_patient(practice_id,created_at desc);
create index if not exists patient_intake_practice_submitted_idx on public.patient_intake_session(practice_id,submitted_at desc) where submitted_at is not null;
create index if not exists coding_validation_practice_open_idx on public.coding_validation_event(practice_id,severity,status) where status in ('open','acknowledged');
create index if not exists scheme_authorisation_practice_created_status_idx on public.scheme_authorisation(practice_id,created_at desc,status);
create index if not exists claim_record_practice_submitted_status_idx on public.claim_record(practice_id,submitted_at desc,claim_status) where submitted_at is not null;
