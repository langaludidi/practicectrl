# Practice Configuration V1: implementation and verification register

Date: 24 September 2026. Branch: `feature/practice-configuration-v1` from the existing audit integration branch (`1a8fd86`), five commits ahead of the current remote `main` (`2adc0e4`). This branch also carries pending Finance access remediation. It is not production code.

## Existing ownership retained

| Concern | Existing authority | V1 action |
| --- | --- | --- |
| Practice identity | `practice`; `practice_billing_profile` | Narrow identity RPC and reuse billing profile; audit changes |
| Locations and practitioners | `practice_location`; `practitioner_profile` | Manage existing records |
| Appointment types | `appointment_type` | Manage existing records; PMS remains booking source |
| Scheme/plan reference | `medical_scheme`; `medical_scheme_option` | Reference shared records, no tenant copies |
| Payer agreement | `payer_contract`; `payer_billing_rule` | Link to the governed agreement workspace |
| Financial decision | `resolve_payer_billing_rule`; `payer_rule_resolution` | Read-only simulator wrapper adds source/version trace; transactions unchanged |
| Work | `operations_work_item` | No duplicate task store; policy-triggered work is pending |

## New durable objects

`practice_operating_config` holds structured PMS handoff, scheduling and intake defaults. `practice_payer_relationship` records scheme acceptance independent of a contract. `practice_policy` holds versioned SOP and structured obligation fields. `practice_configuration_event` records changes (excluding billing banking details). SQL source: `supabase/migrations/20260924180000_practice_configuration_foundation.sql`. Existing Finance staging RLS is separately captured as `supabase/migrations/20260924152752_finance_read_access_alignment_v034.sql`.

All new tenant records carry `practice_id`; authenticated reads require active membership. Updates require MFA level 2 and a practice manager or system administrator. Approved payer/policy versions cannot be rewritten. One active version per payer or policy key is enforced. An approved payer relationship must be retired before another version can activate. Policies cannot enter `active` or `scheduled` until Operations enforcement is connected. The UI provides explicit readiness reasons and an inspectable change history.

## Environment and release gates

Supabase development branching returned `PaymentRequiredException: Branching is supported only on the Pro plan or above`. The existing connected project is the live staging tenant used for first-admin sign-in, so this schema has **not** been applied there. The 162 recorded migration sources have been recovered from the database history, with source digests preserved in `docs/MIGRATION_RECOVERY_MANIFEST.json`; `npm run audit:migrations` verifies all 162. Replay has shown that the recorded history alone is incomplete. Do not point a Vercel Preview with mutation forms at the existing connected project.

The isolated `PracticeCtrl Development` project (`hyajnfdzarbygkvvfbnd`) now exists. A clean replay applied 137 historical migrations, then exposed untracked payer DDL. The schema-only payer foundation was reconstructed from the connected project's catalog as `20260922104000_recovered_payer_foundation.sql`, applied in development, and allowed replay through 149 historical migrations. Migration `20260922184815_communications_automation_v029.sql` then failed because it validates communications automation objects and a cron job created outside the recorded history. The remaining migrations and V1 migration have **not** been applied. No tenant or patient data was copied.

The latest Vercel production deployment serves `2adc0e4`; no Practice Configuration deployment is READY. A separate UX prototype branch exists, but has not been merged into this workspace. This V1 branch must be reconciled with any later main changes before PR promotion.

## Verification status

| Acceptance item | Current evidence |
| --- | --- |
| Identity, branding, provider profile, locations, practitioners, appointment defaults/types | Source implementation; TypeScript and production build pass with placeholder public config. Requires DB and authenticated UI test. |
| Patient administration | Contact, membership and identity defaults stored; full per-category rules and enforcement pending. |
| Schemes and relationships | Shared registry referenced; lifecycle and tenant policies written; migration and role tests pending. |
| Agreements | Existing payer contract lifecycle linked; no replacement. |
| Policies | Versioned drafts, review and approvals stored; executable enforcement and Operations work pending. |
| Readiness and audit | Explicit, linked requirements and change history implemented; business completeness requires review. |
| Simulator and provenance | Reuses existing resolver with service date and added rule/contract version trace; same-rank conflict handling and full rule hierarchy remain Effective Rules V2 work. |
| Isolation | RLS written and statically inspected; cross-tenant authenticated negative tests require isolated database. |
| Preview/UAT | Blocked on separate backend; no claim of production readiness. |

## Non-negotiable boundary

The earlier product decision keeps the PMS authoritative for appointment times, cancellations and rescheduling. The later Diary V2 aspirations in the handoff cannot restore local appointment mutation without resolving that ownership decision. Practice Configuration may define handoff defaults while Requests → PMS confirmation remains the scheduling workflow.
