
begin;

create index if not exists claim_record_patient_idx on public.claim_record(patient_id) where patient_id is not null;
create index if not exists crm_patient_referral_practice_idx on public.crm_patient_referral(practice_id);
create index if not exists crm_timeline_practice_idx on public.crm_timeline_event(practice_id,event_at desc);
create index if not exists vericlaim_import_report_type_idx on public.vericlaim_import_batch(report_type);

drop policy if exists crm_contact_staff_write on public.crm_contact_point;
create policy crm_contact_staff_insert on public.crm_contact_point for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_contact_point.patient_id and m.user_id=(select auth.uid()) and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
));
create policy crm_contact_staff_update on public.crm_contact_point for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_contact_point.patient_id and m.user_id=(select auth.uid()) and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
))
with check (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_contact_point.patient_id and m.user_id=(select auth.uid()) and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
));
create policy crm_contact_staff_delete on public.crm_contact_point for delete to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (
  select 1 from public.crm_patient p join public.practice_staff_member m on m.practice_id=p.practice_id
  where p.id=crm_contact_point.patient_id and m.user_id=(select auth.uid()) and m.active
    and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')
));

drop policy if exists crm_referral_staff_write on public.crm_referral_source;
create policy crm_referral_staff_insert on public.crm_referral_source for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_referral_source.practice_id and m.active and m.role in ('reception','practice_manager','clinical_admin','system_admin')));
create policy crm_referral_staff_update on public.crm_referral_source for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_referral_source.practice_id and m.active and m.role in ('reception','practice_manager','clinical_admin','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=crm_referral_source.practice_id and m.active and m.role in ('reception','practice_manager','clinical_admin','system_admin')));

drop policy if exists billing_validation_finance_write on public.billing_validation_event;
create policy billing_validation_finance_insert on public.billing_validation_event for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_validation_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));
create policy billing_validation_finance_update on public.billing_validation_event for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_validation_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_invoice i join public.practice_staff_member m on m.practice_id=i.practice_id where i.id=billing_validation_event.invoice_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));

drop policy if exists billing_allocation_finance_write on public.billing_payment_allocation;
create policy billing_allocation_finance_insert on public.billing_payment_allocation for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));
create policy billing_allocation_finance_update on public.billing_payment_allocation for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.billing_payment_receipt r join public.practice_staff_member m on m.practice_id=r.practice_id where r.id=billing_payment_allocation.receipt_id and m.user_id=(select auth.uid()) and m.active and m.role in ('billing','practice_manager','system_admin')));

drop policy if exists comm_pref_staff_write on public.communication_preference;
create policy comm_pref_staff_insert on public.communication_preference for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_preference.practice_id and m.active and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')));
create policy comm_pref_staff_update on public.communication_preference for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_preference.practice_id and m.active and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_preference.practice_id and m.active and m.role in ('practitioner','reception','practice_manager','clinical_admin','system_admin')));

drop policy if exists comm_thread_staff_write on public.communication_thread;
create policy comm_thread_staff_insert on public.communication_thread for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_thread.practice_id and m.active and m.role<>'auditor'));
create policy comm_thread_staff_update on public.communication_thread for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_thread.practice_id and m.active and m.role<>'auditor'))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=communication_thread.practice_id and m.active and m.role<>'auditor'));

drop policy if exists comm_message_staff_write on public.communication_message;
create policy comm_message_staff_insert on public.communication_message for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.communication_thread t join public.practice_staff_member m on m.practice_id=t.practice_id where t.id=communication_message.thread_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor'));
create policy comm_message_staff_update on public.communication_message for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.communication_thread t join public.practice_staff_member m on m.practice_id=t.practice_id where t.id=communication_message.thread_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor'))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.communication_thread t join public.practice_staff_member m on m.practice_id=t.practice_id where t.id=communication_message.thread_id and m.user_id=(select auth.uid()) and m.active and m.role<>'auditor'));

drop policy if exists operations_item_staff_write on public.operations_work_item;
create policy operations_item_staff_insert on public.operations_work_item for insert to authenticated
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=operations_work_item.practice_id and m.active and m.role<>'auditor'));
create policy operations_item_staff_update on public.operations_work_item for update to authenticated
using (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=operations_work_item.practice_id and m.active and m.role<>'auditor'))
with check (((select auth.jwt())->>'aal')='aal2' and exists (select 1 from public.practice_staff_member m where m.user_id=(select auth.uid()) and m.practice_id=operations_work_item.practice_id and m.active and m.role<>'auditor'));

commit;
