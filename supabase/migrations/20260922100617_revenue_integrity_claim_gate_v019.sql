
create or replace function public.prepare_claim_from_invoice(p_invoice_id uuid)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid());v_invoice public.billing_invoice%rowtype;v_integrity jsonb;v_claim_id uuid;
begin
 if v_user is null then raise exception 'Authentication required';end if;
 if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required';end if;
 select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found or not accessible';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in('billing','practice_manager','system_admin')) then raise exception 'Billing role required';end if;
 v_integrity:=public.assess_revenue_integrity(p_invoice_id,null,true);
 if coalesce(v_integrity->>'status','blocked')<>'ready' then
   raise exception 'Revenue integrity gate blocked claim preparation: %',jsonb_build_object('score',v_integrity->'score','blocking_count',v_integrity->'blocking_count','warning_count',v_integrity->'warning_count','findings',v_integrity->'findings')::text;
 end if;
 if exists(select 1 from public.claim_record c where c.invoice_id=p_invoice_id and c.claim_status not in('cancelled','reversed')) then raise exception 'An active claim already exists for this invoice';end if;
 insert into public.claim_record(practice_id,invoice_id,patient_id,medical_scheme_id,medical_scheme_option_id,scheme_authorisation_id,claim_status,service_from,service_to,total_claimed,created_by)
 values(v_invoice.practice_id,v_invoice.id,v_invoice.patient_id,v_invoice.medical_scheme_id,v_invoice.medical_scheme_option_id,v_invoice.scheme_authorisation_id,'draft',v_invoice.invoice_date,v_invoice.invoice_date,v_invoice.scheme_portion,v_user) returning id into v_claim_id;
 insert into public.claim_line(claim_id,invoice_line_id,line_no,code_system,code,modifier_codes,diagnosis_codes,quantity,claimed_amount,status)
 select v_claim_id,l.id,l.line_no,l.code_system,l.code,l.modifier_codes,l.diagnosis_codes,l.quantity,l.line_amount,'draft' from public.billing_invoice_line l where l.invoice_id=p_invoice_id and coalesce((l.metadata->>'claim_eligible')::boolean,true)=true order by l.line_no;
 insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata) values(p_invoice_id,'validated',v_user,jsonb_build_object('claim_id',v_claim_id,'claim_prepared',true,'revenue_integrity_score',v_integrity->'score','revenue_integrity_assessment_id',v_integrity->'assessment_id'));
 return v_claim_id;
end $$;
revoke all on function public.prepare_claim_from_invoice(uuid) from public,anon;
grant execute on function public.prepare_claim_from_invoice(uuid) to authenticated;

create or replace function public.authorise_claim_submission(p_claim_id uuid)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_user uuid:=(select auth.uid());c public.claim_record%rowtype;r jsonb;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'AAL2 authentication required';end if;
 select * into c from public.claim_record where id=p_claim_id for update;
 if not found then raise exception 'Claim not found or inaccessible';end if;
 if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=c.practice_id and m.active and m.role in('billing','practice_manager','system_admin')) then raise exception 'Billing role required';end if;
 if c.claim_status not in('draft','validated','ready') then raise exception 'Claim is not in a pre-submission state';end if;
 r:=public.assess_revenue_integrity(c.invoice_id,c.id,true);
 if coalesce(r->>'status','blocked')<>'ready' then raise exception 'Revenue integrity gate blocked claim submission: %',jsonb_build_object('score',r->'score','blocking_count',r->'blocking_count','warning_count',r->'warning_count','findings',r->'findings')::text;end if;
 update public.claim_record set claim_status='ready',updated_at=now() where id=p_claim_id;
 return r||jsonb_build_object('claim_id',p_claim_id,'authorised',true);
end $$;
revoke all on function public.authorise_claim_submission(uuid) from public,anon;
grant execute on function public.authorise_claim_submission(uuid) to authenticated;

