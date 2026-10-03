begin;

grant insert on public.payer_rule_resolution to authenticated;

drop policy if exists payer_resolution_staff_insert on public.payer_rule_resolution;
create policy payer_resolution_staff_insert
on public.payer_rule_resolution
for insert
to authenticated
with check (
  (select current_setting('practicectrl.payer_resolution_mutation',true))='on'
  and ((select auth.jwt())->>'aal')='aal2'
  and resolved_by=(select auth.uid())
  and exists(
    select 1
    from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=payer_rule_resolution.practice_id
      and m.active
      and m.role in ('billing','practice_manager','clinical_admin','system_admin')
  )
);

create or replace function public.record_invoice_line_payer_resolution(
  p_invoice_line_id uuid,
  p_practitioner_id uuid,
  p_reference_amount numeric
)
returns uuid
language plpgsql
security invoker
set search_path to 'public','pg_temp'
as $function$
declare
 v_user uuid:=(select auth.uid());
 l public.billing_invoice_line%rowtype;
 i public.billing_invoice%rowtype;
 j jsonb;
 v_id uuid;
begin
 if v_user is null or coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then
   raise exception 'AAL2 authentication required';
 end if;

 select * into l
 from public.billing_invoice_line
 where id=p_invoice_line_id;
 if not found then raise exception 'Invoice line not found'; end if;

 select * into i from public.billing_invoice where id=l.invoice_id;
 if not found then raise exception 'Invoice not found'; end if;
 if i.status<>'draft' then raise exception 'Payer resolution can only be recorded while the invoice is draft'; end if;

 if not exists(
   select 1
   from public.practice_staff_member m
   where m.user_id=v_user
     and m.practice_id=i.practice_id
     and m.active
     and m.role in('billing','practice_manager','clinical_admin','system_admin')
 ) then
   raise exception 'Billing role required';
 end if;

 perform set_config('practicectrl.billing_line_mutation','on',true);

 select * into l
 from public.billing_invoice_line
 where id=p_invoice_line_id
 for update;
 if not found then
   perform set_config('practicectrl.billing_line_mutation','off',true);
   raise exception 'Invoice line not found or no longer writable';
 end if;

 select * into i from public.billing_invoice where id=l.invoice_id;
 if not found then
   perform set_config('practicectrl.billing_line_mutation','off',true);
   raise exception 'Invoice not found';
 end if;
 if i.status<>'draft' then
   perform set_config('practicectrl.billing_line_mutation','off',true);
   raise exception 'Payer resolution can only be recorded while the invoice is draft';
 end if;

 j:=public.preview_invoice_line_payer_resolution(l.id,p_practitioner_id,p_reference_amount);

 if coalesce((j->>'contract_applicable')::boolean,false)
    and coalesce((j->>'matched')::boolean,false)=false
    and coalesce(jsonb_array_length(j->'requirements'),0)=0 then
   perform set_config('practicectrl.billing_line_mutation','off',true);
   raise exception 'An active payer agreement applies but no effective billing rule matched this line';
 end if;

 perform set_config('practicectrl.payer_resolution_mutation','on',true);

 insert into public.payer_rule_resolution(
   practice_id,invoice_line_id,practitioner_id,medical_scheme_id,medical_scheme_option_id,
   service_date,code_system,code,charged_amount,reference_amount,expected_contractual_amount,
   expected_scheme_amount,expected_patient_liability,applied_rule_id,applied_contract_id,
   precedence_level,confidence,decision_trace,resolved_by
 )
 values(
   i.practice_id,l.id,p_practitioner_id,i.medical_scheme_id,i.medical_scheme_option_id,
   coalesce(l.service_date,i.invoice_date),l.code_system,l.code,l.line_amount,
   nullif(j->>'reference_amount','')::numeric,nullif(j->>'expected_contractual_amount','')::numeric,
   nullif(j->>'expected_scheme_amount','')::numeric,nullif(j->>'estimated_patient_liability','')::numeric,
   nullif(j->>'applied_rule_id','')::uuid,nullif(j->>'applied_contract_id','')::uuid,
   j->>'precedence_level',coalesce(j->>'confidence','low'),jsonb_build_array(j),v_user
 ) returning id into v_id;

 perform set_config('practicectrl.payer_resolution_mutation','off',true);

 update public.billing_invoice_line
 set reference_amount=nullif(j->>'reference_amount','')::numeric,
     expected_contractual_amount=nullif(j->>'expected_contractual_amount','')::numeric,
     expected_scheme_amount=nullif(j->>'expected_scheme_amount','')::numeric,
     expected_patient_liability=nullif(j->>'estimated_patient_liability','')::numeric,
     payer_rule_resolution_id=v_id
 where id=l.id;

 perform set_config('practicectrl.billing_line_mutation','off',true);

 insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
 values(
   i.id,'validated',v_user,jsonb_build_object(
     'payer_resolution_id',v_id,
     'invoice_line_id',l.id,
     'line_no',l.line_no,
     'contract_id',j->'applied_contract_id',
     'rule_id',j->'applied_rule_id',
     'expected_scheme_amount',j->'expected_scheme_amount',
     'expected_patient_liability',j->'estimated_patient_liability',
     'confidence',j->'confidence'
   )
 );

 return v_id;
end
$function$;

revoke all on function public.record_invoice_line_payer_resolution(uuid,uuid,numeric) from public,anon;
grant execute on function public.record_invoice_line_payer_resolution(uuid,uuid,numeric) to authenticated,service_role;

commit;
