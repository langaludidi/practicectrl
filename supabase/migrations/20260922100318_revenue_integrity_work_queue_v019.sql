
create or replace function public.sync_revenue_integrity_work_item()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_patient uuid; v_title text; v_desc text; v_priority text; v_due timestamptz;
begin
 select patient_id into v_patient from public.billing_invoice where id=new.invoice_id and practice_id=new.practice_id;
 if new.status='ready' then
   update public.operations_work_item set status='done',completed_at=coalesce(completed_at,now()),blocked_reason=null,updated_at=now()
   where practice_id=new.practice_id and source_entity_type='revenue_integrity_assessment' and source_entity_id=new.invoice_id and category='revenue_integrity' and status<>'done';
   return new;
 end if;
 v_title:=case when new.status='blocked' then 'Revenue integrity blocker' else 'Revenue integrity review' end;
 v_desc:=new.blocking_count||' blocker(s), '||new.warning_count||' warning(s). Integrity score '||new.score||'/100.';
 v_priority:=case when new.blocking_count>=3 or new.score<40 then 'urgent' when new.blocking_count>0 then 'high' else 'normal' end;
 v_due:=case when v_priority='urgent' then now()+interval '4 hours' when v_priority='high' then now()+interval '1 day' else now()+interval '2 days' end;
 insert into public.operations_work_item(practice_id,patient_id,category,source_entity_type,source_entity_id,title,description,priority,status,due_at,blocked_reason,created_by)
 values(new.practice_id,v_patient,'revenue_integrity','revenue_integrity_assessment',new.invoice_id,v_title,v_desc,v_priority,'open',v_due,case when new.status='blocked' then v_desc else null end,new.assessed_by)
 on conflict(practice_id,source_entity_type,source_entity_id,category) where source_entity_id is not null
 do update set patient_id=excluded.patient_id,title=excluded.title,description=excluded.description,priority=excluded.priority,
   status=case when operations_work_item.status='done' then 'open' else operations_work_item.status end,
   due_at=excluded.due_at,blocked_reason=excluded.blocked_reason,completed_at=null,updated_at=now();
 return new;
end $$;

drop trigger if exists trg_sync_revenue_integrity_work_item on public.revenue_integrity_assessment;
create trigger trg_sync_revenue_integrity_work_item after insert on public.revenue_integrity_assessment for each row execute function public.sync_revenue_integrity_work_item();

create or replace function public.get_revenue_integrity_queue(p_practice_id uuid,p_limit integer default 100)
returns table(invoice_id uuid,invoice_number text,patient_id uuid,patient_name text,invoice_date date,total_amount numeric,balance_amount numeric,scheme_portion numeric,status text,score integer,blocking_count integer,warning_count integer,findings jsonb,assessed_at timestamptz,work_item_id uuid,work_status text,owner_user_id uuid,due_at timestamptz)
language plpgsql stable security invoker set search_path=public,pg_temp as $$
begin
 if (select auth.uid()) is null or not exists(select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=p_practice_id and m.active) then raise exception 'Practice access denied';end if;
 return query
 with latest as (
   select distinct on(a.invoice_id) a.* from public.revenue_integrity_assessment a where a.practice_id=p_practice_id order by a.invoice_id,a.assessed_at desc
 )
 select i.id,i.invoice_number,i.patient_id,p.display_name,i.invoice_date,i.total_amount,i.balance_amount,i.scheme_portion,l.status,l.score,l.blocking_count,l.warning_count,l.findings,l.assessed_at,w.id,w.status,w.owner_user_id,w.due_at
 from latest l join public.billing_invoice i on i.id=l.invoice_id left join public.crm_patient p on p.id=i.patient_id
 left join public.operations_work_item w on w.practice_id=l.practice_id and w.source_entity_type='revenue_integrity_assessment' and w.source_entity_id=l.invoice_id and w.category='revenue_integrity'
 order by case l.status when 'blocked' then 0 when 'review' then 1 else 2 end,l.score asc,i.balance_amount desc
 limit least(greatest(coalesce(p_limit,100),1),500);
end $$;
revoke all on function public.get_revenue_integrity_queue(uuid,integer) from public,anon;
grant execute on function public.get_revenue_integrity_queue(uuid,integer) to authenticated;

create or replace function public.reassess_revenue_integrity(p_invoice_id uuid,p_claim_id uuid default null)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare r jsonb;
begin
 if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 required';end if;
 r:=public.assess_revenue_integrity(p_invoice_id,p_claim_id,true);
 return r;
end $$;
revoke all on function public.reassess_revenue_integrity(uuid,uuid) from public,anon;
grant execute on function public.reassess_revenue_integrity(uuid,uuid) to authenticated;

