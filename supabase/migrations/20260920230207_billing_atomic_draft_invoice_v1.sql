
create or replace function public.create_practice_custom_invoice(
  p_practice_id uuid,
  p_patient_id uuid,
  p_invoice_date date,
  p_description text,
  p_amount numeric,
  p_patient_portion numeric default null,
  p_scheme_portion numeric default null
)
returns uuid
language plpgsql
volatile
security invoker
set search_path=public,pg_temp
as $$
declare
  v_user uuid := (select auth.uid());
  v_invoice_id uuid := gen_random_uuid();
  v_invoice_number text;
  v_patient_portion numeric(14,2);
  v_scheme_portion numeric(14,2);
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'') <> 'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if length(trim(coalesce(p_description,''))) < 2 then raise exception 'Description is required'; end if;

  if not exists (
    select 1 from public.practice_staff_member m
    where m.user_id=v_user and m.practice_id=p_practice_id and m.active
      and m.role in ('billing','practice_manager','system_admin')
  ) then raise exception 'Billing role required'; end if;

  if p_patient_id is not null and not exists (
    select 1 from public.crm_patient p where p.id=p_patient_id and p.practice_id=p_practice_id
  ) then raise exception 'Patient is not in this practice'; end if;

  v_patient_portion := coalesce(p_patient_portion,p_amount);
  v_scheme_portion := coalesce(p_scheme_portion,0);
  if round(v_patient_portion + v_scheme_portion,2) <> round(p_amount,2) then
    raise exception 'Patient and scheme portions must equal invoice total';
  end if;

  v_invoice_number := 'PCD-' || to_char(coalesce(p_invoice_date,current_date),'YYYYMMDD') || '-' || upper(substr(replace(v_invoice_id::text,'-',''),1,8));

  insert into public.billing_invoice(
    id,practice_id,patient_id,invoice_number,invoice_date,status,total_amount,
    scheme_portion,patient_portion,received_amount,balance_amount,source_system,created_by
  ) values (
    v_invoice_id,p_practice_id,p_patient_id,v_invoice_number,coalesce(p_invoice_date,current_date),'draft',p_amount,
    v_scheme_portion,v_patient_portion,0,p_amount,'PracticeCtrl',v_user
  );

  insert into public.billing_invoice_line(
    invoice_id,line_no,code_system,code,description_snapshot,quantity,unit_amount,line_amount,metadata
  ) values (
    v_invoice_id,1,'PRACTICE_CUSTOM','CUSTOM',trim(p_description),1,p_amount,p_amount,
    jsonb_build_object('claim_eligible',false,'source','PracticeCtrl custom draft')
  );

  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(v_invoice_id,'created',v_user,jsonb_build_object('invoice_number',v_invoice_number,'custom_draft',true));

  return v_invoice_id;
end;
$$;

revoke all on function public.create_practice_custom_invoice(uuid,uuid,date,text,numeric,numeric,numeric) from public,anon;
grant execute on function public.create_practice_custom_invoice(uuid,uuid,date,text,numeric,numeric,numeric) to authenticated;
