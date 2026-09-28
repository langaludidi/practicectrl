
do $$
begin
  if to_regclass('public.medicine_reference_ingredient') is null
     or to_regclass('public.medicine_reference_product') is null
     or to_regclass('public.medicine_interaction_rule') is null
     or to_regclass('public.patient_allergy') is null
     or to_regclass('public.patient_medication') is null
     or to_regclass('public.medication_reconciliation_session') is null
     or to_regclass('public.medication_reconciliation_item') is null
     or to_regclass('public.prescription') is null
     or to_regclass('public.prescription_item') is null
     or to_regclass('public.prescription_safety_assessment') is null
     or to_regclass('public.prescription_safety_finding') is null
     or to_regclass('public.prescription_transmission_request') is null
  then raise exception 'PracticeCtrl v0.31 medicines schema is incomplete'; end if;

  if to_regprocedure('public.create_prescription_draft(uuid,uuid,uuid,text,text,jsonb)') is null
     or to_regprocedure('public.assess_prescription_safety(uuid)') is null
     or to_regprocedure('public.approve_prescription(uuid)') is null
     or to_regprocedure('public.queue_prescription_transmission(uuid,uuid,text)') is null
     or to_regprocedure('public.start_medication_reconciliation(uuid,uuid,uuid,text)') is null
     or to_regprocedure('public.complete_medication_reconciliation(uuid)') is null
     or to_regprocedure('public.get_medicines_readiness(uuid)') is null
     or to_regprocedure('public.get_medicines_metrics(uuid,integer)') is null
  then raise exception 'PracticeCtrl v0.31 medicines RPC set is incomplete'; end if;

  if not exists(select 1 from public.integration_provider where slug='emguidance-script' and lifecycle_status='contact_required') then
    raise exception 'PracticeCtrl v0.31 e-prescribing provider boundary is not fail-closed';
  end if;

  if exists(
    select 1 from public.integration_adapter_capability ac
    join public.integration_provider p on p.id=ac.provider_id
    where p.slug='emguidance-script' and ac.capability_code='prescription_transmit'
      and (ac.executable_sandbox or ac.executable_production)
  ) then raise exception 'PracticeCtrl v0.31 must not mark EMGuidance prescription transmission executable without conformance'; end if;
end $$;
