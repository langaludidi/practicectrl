
create or replace function public.get_practicectrl_operational_analytics(p_practice_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=public,pg_temp
as $$
select jsonb_build_object(
  'operations',jsonb_build_object(
    'open',count(*) filter(where w.status in ('open','in_progress','waiting','blocked')),
    'overdue',count(*) filter(where w.status in ('open','in_progress','waiting','blocked') and w.due_at is not null and w.due_at<now()),
    'blocked',count(*) filter(where w.status='blocked'),
    'unassigned',count(*) filter(where w.status in ('open','in_progress','waiting','blocked') and w.owner_user_id is null),
    'urgent_open',count(*) filter(where w.status in ('open','in_progress','waiting','blocked') and w.priority='urgent')
  ),
  'requests_by_status',coalesce((
    select jsonb_object_agg(status,cnt)
    from (select r.status,count(*) cnt from public.appointment_request r where r.practice_id=p_practice_id group by r.status) x
  ),'{}'::jsonb),
  'claims_by_status',coalesce((
    select jsonb_object_agg(claim_status,cnt)
    from (select c.claim_status,count(*) cnt from public.claim_record c where c.practice_id=p_practice_id group by c.claim_status) x
  ),'{}'::jsonb),
  'communication_by_status',coalesce((
    select jsonb_object_agg(status,cnt)
    from (
      select msg.status,count(*) cnt
      from public.communication_message msg
      join public.communication_thread t on t.id=msg.thread_id
      where t.practice_id=p_practice_id
      group by msg.status
    ) x
  ),'{}'::jsonb),
  'encounters',jsonb_build_object(
    'total_30d',(select count(*) from public.practice_encounter e where e.practice_id=p_practice_id and e.service_date>=current_date-29),
    'open',(select count(*) from public.practice_encounter e where e.practice_id=p_practice_id and e.status='open'),
    'completed_30d',(select count(*) from public.practice_encounter e where e.practice_id=p_practice_id and e.status='completed' and e.service_date>=current_date-29)
  ),
  'billing',jsonb_build_object(
    'draft',(select count(*) from public.billing_invoice i where i.practice_id=p_practice_id and i.status='draft'),
    'final_open',(select count(*) from public.billing_invoice i where i.practice_id=p_practice_id and i.status in ('final','part_paid','outstanding')),
    'open_balance',coalesce((select sum(i.balance_amount) from public.billing_invoice i where i.practice_id=p_practice_id and i.status in ('final','part_paid','outstanding')),0),
    'receipts_30d',coalesce((select sum(abs(r.amount)) from public.billing_payment_receipt r where r.practice_id=p_practice_id and r.receipt_date>=current_date-29),0)
  ),
  'claims',jsonb_build_object(
    'claimed_total',coalesce((select sum(c.total_claimed) from public.claim_record c where c.practice_id=p_practice_id),0),
    'paid_total',coalesce((select sum(c.total_paid) from public.claim_record c where c.practice_id=p_practice_id),0),
    'exception_count',(select count(*) from public.claim_record c where c.practice_id=p_practice_id and c.claim_status in ('rejected','exception','partially_accepted'))
  )
)
from public.operations_work_item w
where w.practice_id=p_practice_id;
$$;
revoke all on function public.get_practicectrl_operational_analytics(uuid) from public,anon;
grant execute on function public.get_practicectrl_operational_analytics(uuid) to authenticated;

