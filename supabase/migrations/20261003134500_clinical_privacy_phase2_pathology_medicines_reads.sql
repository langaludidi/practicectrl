begin;

-- Phase 2 clinical privacy: restrict patient-specific pathology and medicines reads
-- to practitioners. Reference/configuration tables remain governed separately.

drop policy if exists pathology_ai_review_read on public.pathology_ai_review;
create policy pathology_ai_review_read on public.pathology_ai_review for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_ai_review.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_ai_review_source_read on public.pathology_ai_review_source;
create policy pathology_ai_review_source_read on public.pathology_ai_review_source for select to authenticated using (
  exists(
    select 1
    from public.pathology_ai_review r
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=pathology_ai_review_source.review_id
      and m.user_id=(select auth.uid()) and m.active and m.role='practitioner'
  )
);

drop policy if exists pathology_follow_up_read on public.pathology_follow_up_action;
create policy pathology_follow_up_read on public.pathology_follow_up_action for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_follow_up_action.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_order_clinical_read on public.pathology_order;
create policy pathology_order_clinical_read on public.pathology_order for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_order.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_order_item_clinical_read on public.pathology_order_item;
create policy pathology_order_item_clinical_read on public.pathology_order_item for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_order_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_clinical_read on public.pathology_result;
create policy pathology_result_clinical_read on public.pathology_result for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_result.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_item_clinical_read on public.pathology_result_item;
create policy pathology_result_item_clinical_read on public.pathology_result_item for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_result_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_ack_clinical_read on public.pathology_result_acknowledgement;
create policy pathology_ack_clinical_read on public.pathology_result_acknowledgement for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_result_acknowledgement.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_doc_clinical_read on public.pathology_result_document;
create policy pathology_doc_clinical_read on public.pathology_result_document for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_result_document.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_inbox_read on public.pathology_result_inbox;
create policy pathology_inbox_read on public.pathology_result_inbox for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_result_inbox.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_release_read on public.pathology_result_release;
create policy pathology_result_release_read on public.pathology_result_release for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_result_release.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_safety_case_read on public.pathology_safety_case;
create policy pathology_safety_case_read on public.pathology_safety_case for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_safety_case.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_safety_event_read on public.pathology_safety_event;
create policy pathology_safety_event_read on public.pathology_safety_event for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_safety_event.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_specimen_read on public.pathology_specimen;
create policy pathology_specimen_read on public.pathology_specimen for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_specimen.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_specimen_event_read on public.pathology_specimen_event;
create policy pathology_specimen_event_read on public.pathology_specimen_event for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=pathology_specimen_event.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists med_recon_item_read on public.medication_reconciliation_item;
create policy med_recon_item_read on public.medication_reconciliation_item for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=medication_reconciliation_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists med_recon_session_read on public.medication_reconciliation_session;
create policy med_recon_session_read on public.medication_reconciliation_session for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=medication_reconciliation_session.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists medicines_ai_review_read on public.medicines_ai_review;
create policy medicines_ai_review_read on public.medicines_ai_review for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=medicines_ai_review.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists medicines_ai_review_source_read on public.medicines_ai_review_source;
create policy medicines_ai_review_source_read on public.medicines_ai_review_source for select to authenticated using (
  exists(
    select 1
    from public.medicines_ai_review r
    join public.practice_staff_member m on m.practice_id=r.practice_id
    where r.id=medicines_ai_review_source.review_id
      and m.user_id=(select auth.uid()) and m.active and m.role='practitioner'
  )
);

drop policy if exists medicines_ai_source_read on public.medicines_ai_source_file;
create policy medicines_ai_source_read on public.medicines_ai_source_file for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=medicines_ai_source_file.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists patient_allergy_read on public.patient_allergy;
create policy patient_allergy_read on public.patient_allergy for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=patient_allergy.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists patient_medication_read on public.patient_medication;
create policy patient_medication_read on public.patient_medication for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=patient_medication.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists prescription_read on public.prescription;
create policy prescription_read on public.prescription for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=prescription.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists prescription_item_read on public.prescription_item;
create policy prescription_item_read on public.prescription_item for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=prescription_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists prescription_safety_read on public.prescription_safety_assessment;
create policy prescription_safety_read on public.prescription_safety_assessment for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=prescription_safety_assessment.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists prescription_finding_read on public.prescription_safety_finding;
create policy prescription_finding_read on public.prescription_safety_finding for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=prescription_safety_finding.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists prescription_tx_read on public.prescription_transmission_request;
create policy prescription_tx_read on public.prescription_transmission_request for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=prescription_transmission_request.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists prescription_tx_event_read on public.prescription_transmission_event;
create policy prescription_tx_event_read on public.prescription_transmission_event for select to authenticated using (
  exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid()) and m.practice_id=prescription_transmission_event.practice_id
      and m.active and m.role='practitioner')
);

-- Patient clinical file buckets follow the same practitioner-only read boundary.
drop policy if exists pathology_result_files_read on storage.objects;
create policy pathology_result_files_read on storage.objects for select to authenticated using (
  bucket_id='pathology-result-files'
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=((storage.foldername(objects.name))[1])::uuid
      and m.active and m.role='practitioner'
  )
);

drop policy if exists medicines_ai_files_read on storage.objects;
create policy medicines_ai_files_read on storage.objects for select to authenticated using (
  bucket_id='medicines-ai-files'
  and exists(
    select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=((storage.foldername(objects.name))[1])::uuid
      and m.active and m.role='practitioner'
  )
);

commit;
