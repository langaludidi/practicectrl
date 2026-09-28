
create unique index patient_intake_consent_document_scope_uq
on public.patient_intake_consent_document(coalesce(practice_id,'00000000-0000-0000-0000-000000000000'::uuid),consent_key,version);

