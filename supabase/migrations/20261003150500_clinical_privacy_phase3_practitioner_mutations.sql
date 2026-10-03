begin;

-- Phase 3 clinical privacy: direct patient-clinical mutations by authenticated users
-- are practitioner-only. Service-role integrations remain unaffected by RLS.

-- Pathology orders and order items.
drop policy if exists pathology_order_clinical_insert on public.pathology_order;
create policy pathology_order_clinical_insert on public.pathology_order
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_order.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_order_clinical_update on public.pathology_order;
create policy pathology_order_clinical_update on public.pathology_order
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_order.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_order.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_order_item_clinical_insert on public.pathology_order_item;
create policy pathology_order_item_clinical_insert on public.pathology_order_item
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_order_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_order_item_clinical_update on public.pathology_order_item;
create policy pathology_order_item_clinical_update on public.pathology_order_item
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_order_item.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_order_item.practice_id
      and m.active and m.role='practitioner')
);

-- Pathology results, result items, acknowledgement, documents and inbox.
drop policy if exists pathology_result_clinical_insert on public.pathology_result;
create policy pathology_result_clinical_insert on public.pathology_result
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_clinical_update on public.pathology_result;
create policy pathology_result_clinical_update on public.pathology_result
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_item_clinical_insert on public.pathology_result_item;
create policy pathology_result_item_clinical_insert on public.pathology_result_item
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_item_clinical_update on public.pathology_result_item;
create policy pathology_result_item_clinical_update on public.pathology_result_item
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_item.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_ack_clinical_insert on public.pathology_result_acknowledgement;
create policy pathology_ack_clinical_insert on public.pathology_result_acknowledgement
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and acknowledged_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_acknowledgement.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_ack_clinical_update on public.pathology_result_acknowledgement;
create policy pathology_ack_clinical_update on public.pathology_result_acknowledgement
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_acknowledgement.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and acknowledged_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_acknowledgement.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_doc_clinical_insert on public.pathology_result_document;
create policy pathology_doc_clinical_insert on public.pathology_result_document
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_document.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_doc_clinical_update on public.pathology_result_document;
create policy pathology_doc_clinical_update on public.pathology_result_document
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_document.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_document.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_inbox_insert on public.pathology_result_inbox;
create policy pathology_inbox_insert on public.pathology_result_inbox
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and (created_by is null or created_by=(select auth.uid()))
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_inbox.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_inbox_update on public.pathology_result_inbox;
create policy pathology_inbox_update on public.pathology_result_inbox
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_inbox.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_inbox.practice_id
      and m.active and m.role='practitioner')
);

-- Pathology follow-up, release and specimen handling.
drop policy if exists pathology_follow_up_insert on public.pathology_follow_up_action;
create policy pathology_follow_up_insert on public.pathology_follow_up_action
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_follow_up_action.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_follow_up_update on public.pathology_follow_up_action;
create policy pathology_follow_up_update on public.pathology_follow_up_action
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_follow_up_action.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_follow_up_action.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_release_insert on public.pathology_result_release;
create policy pathology_result_release_insert on public.pathology_result_release
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_release.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_result_release_update on public.pathology_result_release;
create policy pathology_result_release_update on public.pathology_result_release
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_release.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_result_release.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_specimen_insert on public.pathology_specimen;
create policy pathology_specimen_insert on public.pathology_specimen
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_specimen.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists pathology_specimen_update on public.pathology_specimen;
create policy pathology_specimen_update on public.pathology_specimen
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_specimen.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=pathology_specimen.practice_id
      and m.active and m.role='practitioner')
);

-- Medicines and reconciliation.
drop policy if exists patient_allergy_insert on public.patient_allergy;
create policy patient_allergy_insert on public.patient_allergy
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and (recorded_by is null or recorded_by=(select auth.uid()))
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_allergy.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists patient_allergy_update on public.patient_allergy;
create policy patient_allergy_update on public.patient_allergy
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_allergy.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_allergy.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists patient_medication_insert on public.patient_medication;
create policy patient_medication_insert on public.patient_medication
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and (created_by is null or created_by=(select auth.uid()))
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_medication.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists patient_medication_update on public.patient_medication;
create policy patient_medication_update on public.patient_medication
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_medication.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=patient_medication.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists med_recon_session_insert on public.medication_reconciliation_session;
create policy med_recon_session_insert on public.medication_reconciliation_session
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and started_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medication_reconciliation_session.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists med_recon_session_update on public.medication_reconciliation_session;
create policy med_recon_session_update on public.medication_reconciliation_session
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medication_reconciliation_session.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medication_reconciliation_session.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists med_recon_item_insert on public.medication_reconciliation_item;
create policy med_recon_item_insert on public.medication_reconciliation_item
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medication_reconciliation_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists med_recon_item_update on public.medication_reconciliation_item;
create policy med_recon_item_update on public.medication_reconciliation_item
for update to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medication_reconciliation_item.practice_id
      and m.active and m.role='practitioner')
)
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medication_reconciliation_item.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists medicines_ai_source_insert on public.medicines_ai_source_file;
create policy medicines_ai_source_insert on public.medicines_ai_source_file
for insert to authenticated
with check (
  ((select auth.jwt())->>'aal')='aal2'
  and created_by=(select auth.uid())
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medicines_ai_source_file.practice_id
      and m.active and m.role='practitioner')
);

drop policy if exists medicines_ai_source_delete on public.medicines_ai_source_file;
create policy medicines_ai_source_delete on public.medicines_ai_source_file
for delete to authenticated
using (
  ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=medicines_ai_source_file.practice_id
      and m.active and m.role='practitioner')
);

-- Private clinical file buckets: authenticated patient-clinical file writes are practitioner-only.
drop policy if exists pathology_result_files_insert on storage.objects;
create policy pathology_result_files_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='pathology-result-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=((storage.foldername(objects.name))[1])::uuid
      and m.active and m.role='practitioner')
);

drop policy if exists medicines_ai_files_insert on storage.objects;
create policy medicines_ai_files_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='medicines-ai-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=((storage.foldername(objects.name))[1])::uuid
      and m.active and m.role='practitioner')
);

drop policy if exists medicines_ai_files_delete on storage.objects;
create policy medicines_ai_files_delete on storage.objects
for delete to authenticated
using (
  bucket_id='medicines-ai-files'
  and ((select auth.jwt())->>'aal')='aal2'
  and exists(select 1 from public.practice_staff_member m
    where m.user_id=(select auth.uid())
      and m.practice_id=((storage.foldername(objects.name))[1])::uuid
      and m.active and m.role='practitioner')
);

commit;
