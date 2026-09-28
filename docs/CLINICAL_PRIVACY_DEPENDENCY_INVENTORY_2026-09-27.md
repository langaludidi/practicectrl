# Clinical privacy dependency inventory — 27 September 2026

This inventory implements the sequencing in the Product Decisions & Build Handoff v1.1, §3.1 and §34. It is a development-branch finding, not clinical access sign-off.

## Current consumers

| Surface | Detailed data queried | Intended access / dependency |
| --- | --- | --- |
| `/clinical` | Notes (including narrative, assessment and plan), observations | Practitioner only; the server route now enforces this through `canViewClinicalRecords`. |
| `/pathology` | Orders, results, result items, comments, files and AI reviews | Practitioner only for the full workspace. Operational readiness needs a separate minimum-necessary projection. |
| `/medicines` | Allergies, medication reconciliation, prescriptions and safety findings | Practitioner only for the full workspace. Other workflows need explicit status/obligation outputs. |
| `/patients/[id]` | Clinical note title/assessment when allowed; document titles/types for all staff | Clinical note query is conditional on practitioner role. Clinical documents are still returned to non-practitioner roles by current RLS. |
| `/documents` | Patient documents with `clinical_data` and title; templates | A mixed administrative and clinical workflow. Split clinical documents from administrative documents before restricting row access. |
| Billing, claims, authorisations, Operations | Coding, authorisation, readiness, financial and work states | Keep structured outputs and existing transaction ownership; do not expose note narrative or full results to satisfy these dependencies. |

## Database findings

- Current `clinical_note`, `clinical_note_diagnosis`, `clinical_note_event` and `clinical_observation` SELECT policies include practitioner, clinical administrator, practice manager, system administrator and auditor. Frontend hiding alone is not a data boundary.
- The recovered pathology and medicines schema has the same broad clinical read set on patient data. Reference terminology tables are separate and may remain accessible to appropriate staff.
- `patient_document` permits every active staff member to read nonclinical rows and grants the five broad clinical roles access to `clinical_data=true` rows. The patient and documents routes currently consume those rows.
- Storage object policies for private pathology and medicines files and all security-definer RPCs need review alongside table RLS.
- UI getters were narrowed to practitioner for the Clinical, Pathology and Medicines workspaces on the feature branch. Database policy alignment has **not** been applied.

## Safe migration order

1. Define a structured, tenant-scoped operational view/RPC for appointment readiness and document status with only the fields needed by reception, billing and Operations. Confirm each consumer uses that output.
2. Split the document list into nonclinical administrative documents and practitioner-only clinical documents. Avoid exposing clinical titles through an all-staff listing.
3. Review all clinical/pathology/medicines SELECT and mutation policies, storage policies and security-definer functions; then apply one controlled RLS migration, including patient documents.
4. Test each of the nine roles in two synthetic tenants, including direct table and RPC negative reads, storage access, and practitioner positive actions. Test the operational projections still work without narrative access.
5. Run the application build and role-based browser UAT against an isolated preview before promoting the migration.

`docs/CLINICAL_PRIVACY_ALIGNMENT_DRAFT.sql` contains a partial policy sketch for the four original clinical tables. It is deliberately outside `supabase/migrations/` and must not be applied or promoted as a complete privacy fix.
