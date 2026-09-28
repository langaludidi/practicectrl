
create or replace function public.sync_revenue_integrity_work_item()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_patient uuid; v_title text; v_desc text; v_priority text; v_due timestamptz;
begin
 select patient_id into v_patient from public.billing_invoice where id=new.invoice_id and practice_id=new.practice_id;
 if new.status='ready' then
   update public.operations_work_item
   set status='completed',completed_at=coalesce(completed_at,now()),blocked_reason=null,updated_at=now()
   where practice_id=new.practice_id
     and source_entity_type='revenue_integrity_assessment'
     and source_entity_id=new.invoice_id
     and category='revenue_integrity'
     and status not in('completed','cancelled');
   return new;
 end if;
 v_title:=case when new.status='blocked' then 'Revenue integrity blocker' else 'Revenue integrity review' end;
 v_desc:=new.blocking_count||' blocker(s), '||new.warning_count||' warning(s). Integrity score '||new.score||'/100.';
 v_priority:=case when new.blocking_count>=3 or new.score<40 then 'urgent' when new.blocking_count>0 then 'high' else 'normal' end;
 v_due:=public.pc_due_at(new.practice_id,'revenue_integrity',v_priority,case when v_priority='urgent' then 240 when v_priority='high' then 1440 else 2880 end);
 insert into public.operations_work_item(practice_id,patient_id,category,source_entity_type,source_entity_id,title,description,priority,status,due_at,blocked_reason,created_by)
 values(new.practice_id,v_patient,'revenue_integrity','revenue_integrity_assessment',new.invoice_id,v_title,v_desc,v_priority,'open',v_due,case when new.status='blocked' then v_desc else null end,new.assessed_by)
 on conflict(practice_id,source_entity_type,source_entity_id,category) where source_entity_id is not null
 do update set patient_id=excluded.patient_id,title=excluded.title,description=excluded.description,priority=excluded.priority,
   status=case when public.operations_work_item.status='completed' then 'open' else public.operations_work_item.status end,
   due_at=case when public.operations_work_item.status='completed' then excluded.due_at else public.operations_work_item.due_at end,
   blocked_reason=excluded.blocked_reason,completed_at=null,updated_at=now();
 return new;
end $$;

