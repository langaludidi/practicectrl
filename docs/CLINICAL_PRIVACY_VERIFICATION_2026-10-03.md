# Clinical privacy verification — 3 October 2026

## Product boundary

PracticeCtrl Clinical is practitioner-only. Non-practitioner roles may receive minimum-necessary structured outputs for authorised administrative or financial workflows, but not unrestricted clinical narrative, results, medicines or other patient-clinical data.

## Changes verified

### Phase 1 — notes and clinical documents

The development database now enforces practitioner-only access for:

- clinical notes;
- note diagnoses;
- note events;
- clinical observations;
- patient documents marked `clinical_data=true`.

Administrative patient documents remain available to authorised non-practitioner staff.

The patient record and Documents workspace also filter clinical documents from non-practitioner roles at application level.

### Phase 2 — pathology and medicines reads

Patient-specific pathology and medicines SELECT policies now require an active same-practice practitioner.

This includes pathology orders/results, result items, acknowledgements, clinical result documents, inbox, safety/follow-up records, medication history, allergies, medication reconciliation, prescriptions, safety findings and patient-specific AI review/source records.

Private pathology-result and medicines-AI file-bucket reads are practitioner-only.

### Phase 3 — clinical mutations

Authenticated writes to patient-specific pathology, medicines, allergy and medication-reconciliation records now require:

- AAL2; and
- active same-practice practitioner membership.

Service-role integrations continue through the existing server/integration boundary and are not converted into practitioner sessions.

Prescription policies were already practitioner/prescriber-specific and remain so.

## Regression evidence

Rollback-only synthetic tests on **PracticeCtrl Development** verified:

- a practice manager cannot read core clinical notes or clinical documents;
- a practice manager cannot read patient allergies, pathology orders or pathology results;
- a clinical administrator cannot insert a patient allergy;
- a clinical administrator cannot insert a pathology order;
- a clinical-administrator call to the medication-recording RPC cannot bypass RLS;
- an authorised practitioner can read and write the tested clinical records;
- administrative patient-document access remains available where the document is non-clinical.

## Important remaining privacy work

- Several legacy clinical RPC bodies still contain historical `clinical_admin` role checks. They are now stopped by practitioner-only table RLS, so they do not create a current data-access bypass, but the role checks should be cleaned up to match the product contract and provide clearer errors.
- `pathology_audit_event` still needs a specific decision: either make raw clinical audit metadata practitioner-only or expose a separate minimum-necessary governance projection to auditors/managers.
- Full role regression must cover all configured role families before production promotion.
- Any new clinical table must default to the practitioner-only data boundary unless an explicit minimum-necessary projection is designed.
