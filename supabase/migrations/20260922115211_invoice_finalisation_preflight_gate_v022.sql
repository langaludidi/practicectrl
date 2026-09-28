
create or replace function public.finalise_billing_invoice(p_invoice_id uuid)
returns uuid
language plpgsql
set search_path to 'public','pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  v_invoice public.billing_invoice%rowtype;
  v_profile public.practice_billing_profile%rowtype;
  v_line_count integer;
  v_subtotal numeric(14,2);
  v_tax numeric(14,2);
  v_total numeric(14,2);
  v_liability_total numeric(14,2);
  v_account uuid;
  v_kind text;
  v_preflight jsonb;
  r record;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if coalesce((select auth.jwt()->>'aal'),'')<>'aal2' then raise exception 'MFA assurance level 2 required'; end if;
  select * into v_invoice from public.billing_invoice where id=p_invoice_id for update;
  if not found then raise exception 'Invoice not found or not accessible'; end if;
  if v_invoice.status<>'draft' then raise exception 'Only draft invoices can be finalised'; end if;
  if not exists(select 1 from public.practice_staff_member m where m.user_id=v_user and m.practice_id=v_invoice.practice_id and m.active and m.role in ('billing','practice_manager','system_admin')) then raise exception 'Billing role required'; end if;

  if exists(select 1 from public.billing_invoice_line where invoice_id=p_invoice_id and claim_eligible) then
    v_preflight:=public.run_invoice_claim_preflight(p_invoice_id,true);
    if coalesce(v_preflight->>'status','blocked')='blocked' then
      raise exception 'Claim pre-flight blocked invoice finalisation: %',
        jsonb_build_object('blocking_count',v_preflight->'blocking_count','findings',v_preflight->'findings')::text;
    end if;
  end if;

  select count(*),coalesce(sum(line_amount-tax_amount),0),coalesce(sum(tax_amount),0),coalesce(sum(line_amount),0),
         case when bool_and(line_type='clinical') then 'clinical' when bool_and(line_type='transactional') then 'transactional' else 'mixed' end
  into v_line_count,v_subtotal,v_tax,v_total,v_kind from public.billing_invoice_line where invoice_id=p_invoice_id;
  if v_line_count<1 then raise exception 'Invoice has no lines'; end if;
  if v_invoice.account_id is null then
    if v_invoice.patient_id is null then raise exception 'A liable billing account is required before finalisation'; end if;
    v_account:=public.ensure_patient_billing_account(v_invoice.practice_id,v_invoice.patient_id);
    update public.billing_invoice set account_id=v_account,recipient_snapshot=public.billing_recipient_snapshot(v_account) where id=p_invoice_id;
    v_invoice.account_id:=v_account;
  end if;
  if not exists(select 1 from public.billing_invoice_liability where invoice_id=p_invoice_id) then
    insert into public.billing_invoice_liability(practice_id,invoice_id,account_id,liability_type,amount)
    select v_invoice.practice_id,p_invoice_id,a.id,case when a.account_type='patient' then 'patient' when a.account_type='medical_scheme' then 'scheme' else 'other' end,v_total
    from public.billing_account a where a.id=v_invoice.account_id;
  end if;
  select coalesce(sum(amount),0) into v_liability_total from public.billing_invoice_liability where invoice_id=p_invoice_id;
  if round(v_liability_total,2)<>round(v_total,2) then raise exception 'Invoice liability split must equal invoice total'; end if;
  select * into v_profile from public.practice_billing_profile where practice_id=v_invoice.practice_id;
  if v_tax>0 and not coalesce(v_profile.vat_registered,false) then raise exception 'VAT cannot be charged because this practice is not configured as VAT registered'; end if;
  if coalesce(v_profile.vat_registered,false) and nullif(trim(coalesce(v_profile.vat_registration_number,'')),'') is null then raise exception 'VAT registration number is required before issuing a tax invoice'; end if;
  if exists(select 1 from public.billing_validation_event e where e.invoice_id=p_invoice_id and e.severity='blocking' and e.status in ('open','acknowledged')) then
    raise exception 'Unresolved blocking billing validation exists';
  end if;

  perform set_config('practicectrl.billing_posting','on',true);
  update public.billing_invoice set
    invoice_kind=v_kind,subtotal_amount=v_subtotal,tax_amount=v_tax,total_amount=v_total,
    patient_portion=coalesce((select sum(amount) from public.billing_invoice_liability where invoice_id=p_invoice_id and liability_type='patient'),0),
    scheme_portion=coalesce((select sum(amount) from public.billing_invoice_liability where invoice_id=p_invoice_id and liability_type='scheme'),0),
    balance_amount=greatest(v_total-credited_amount-received_amount,0),tax_invoice=coalesce(v_profile.vat_registered,false),
    supplier_snapshot=public.billing_supplier_snapshot(v_invoice.practice_id),recipient_snapshot=public.billing_recipient_snapshot(v_invoice.account_id),
    status=case when greatest(v_total-credited_amount-received_amount,0)=0 then 'paid' else 'final' end,
    finalised_by=v_user,finalised_at=now(),updated_at=now()
  where id=p_invoice_id;

  for r in select * from public.billing_invoice_liability where invoice_id=p_invoice_id and amount>0 loop
    insert into public.billing_ledger_entry(practice_id,account_id,transaction_date,entry_type,document_number,description,signed_amount,invoice_id,source_key,created_by,metadata)
    values(v_invoice.practice_id,r.account_id,v_invoice.invoice_date,'invoice',v_invoice.invoice_number,'Invoice '||v_invoice.invoice_number,r.amount,p_invoice_id,'invoice:'||p_invoice_id::text||':'||r.id::text,v_user,jsonb_build_object('liability_type',r.liability_type))
    on conflict(practice_id,source_key) do nothing;
  end loop;
  insert into public.billing_invoice_event(invoice_id,event_type,actor_user_id,metadata)
  values(p_invoice_id,'finalised',v_user,jsonb_build_object(
    'line_count',v_line_count,'total_amount',v_total,'tax_amount',v_tax,'liability_total',v_liability_total,
    'invoice_kind',v_kind,'payer_contract_gate','passed','payer_contract_id',v_invoice.payer_contract_id,
    'claim_preflight_status',coalesce(v_preflight->>'status','not_applicable'),
    'claim_preflight_blocking_count',coalesce((v_preflight->>'blocking_count')::integer,0),
    'claim_preflight_warning_count',coalesce((v_preflight->>'warning_count')::integer,0)
  ));
  perform set_config('practicectrl.billing_posting','off',true);
  return p_invoice_id;
end
$function$;

revoke all on function public.finalise_billing_invoice(uuid) from public,anon;
grant execute on function public.finalise_billing_invoice(uuid) to authenticated,service_role;

