do $$
declare r record;
begin
  for r in
    select con.conname, con.conrelid::regclass as table_name,
           string_agg(format('%I',att.attname),',' order by u.ord) as cols
    from pg_constraint con
    join unnest(con.conkey) with ordinality u(attnum,ord) on true
    join pg_attribute att on att.attrelid=con.conrelid and att.attnum=u.attnum
    where con.contype='f' and con.connamespace='public'::regnamespace
      and con.conname = any(array[
        'appointment_event_actor_user_id_fkey','appointment_type_created_by_fkey','appointment_waitlist_appointment_type_id_fkey','appointment_waitlist_created_by_fkey','appointment_waitlist_patient_id_fkey','appointment_waitlist_practitioner_id_fkey',
        'clinical_prebill_handoff_coding_decision_id_fkey','clinical_prebill_handoff_coding_session_id_fkey','clinical_prebill_handoff_converted_by_fkey','clinical_prebill_handoff_converted_invoice_id_fkey','clinical_prebill_handoff_converted_invoice_line_id_fkey','clinical_prebill_handoff_created_by_fkey','clinical_prebill_handoff_medical_scheme_id_fkey','clinical_prebill_handoff_medical_scheme_option_id_fkey','clinical_prebill_handoff_membership_id_fkey','clinical_prebill_handoff_patient_id_fkey','clinical_prebill_handoff_payer_contract_id_fkey','clinical_prebill_handoff_practitioner_id_fkey',
        'patient_address_created_by_fkey','patient_address_practice_id_fkey','patient_communication_preference_practice_id_fkey','patient_communication_preference_updated_by_fkey','patient_emergency_contact_created_by_fkey','patient_emergency_contact_practice_id_fkey','patient_intake_consent_document_created_by_fkey','patient_intake_event_actor_user_id_fkey','patient_intake_match_candidate_patient_id_fkey','patient_intake_match_candidate_reviewed_by_fkey','patient_intake_merge_decision_decided_by_fkey','patient_intake_session_applied_patient_id_fkey','patient_intake_session_created_by_fkey','patient_intake_session_existing_patient_id_fkey','patient_intake_session_reviewed_by_fkey',
        'practice_appointment_appointment_type_id_fkey','practice_appointment_created_by_fkey','practice_appointment_updated_by_fkey','practice_location_created_by_fkey','practitioner_availability_rule_created_by_fkey','practitioner_availability_rule_location_id_fkey','practitioner_availability_rule_practice_id_fkey','practitioner_profile_created_by_fkey','practitioner_profile_default_location_id_fkey','practitioner_schedule_exception_created_by_fkey','practitioner_schedule_exception_practice_id_fkey',
        'procedure_tariff_import_batch_code_system_fkey','procedure_tariff_import_batch_created_by_fkey','procedure_tariff_import_batch_dataset_id_fkey','procedure_tariff_import_batch_published_by_fkey','procedure_tariff_import_batch_reviewed_by_fkey','procedure_tariff_import_batch_tariff_schedule_id_fkey','revenue_integrity_assessment_assessed_by_fkey','revenue_integrity_assessment_claim_id_fkey','revenue_integrity_assessment_invoice_id_fkey','scheme_membership_verification_case_requested_by_fkey','scheme_membership_verification_case_resolved_by_fkey'
      ])
    group by con.conname,con.conrelid
  loop
    execute format('create index if not exists %I on %s (%s)',regexp_replace(r.conname,'_fkey$','_idx'),r.table_name,r.cols);
  end loop;
end $$;
