# Practice Configuration V1 — development evidence, 27 September 2026

Environment: isolated Supabase development project `hyajnfdzarbygkvvfbnd`; branch `feature/practice-configuration-v1`. The existing Dr Tini project remains paused. No synthetic patient or credential data was copied from it.

## Schema replay

- The 162 recorded historical migrations and nine recovered missing foundations replayed in order. `20260924180000_practice_configuration_foundation.sql` then applied successfully. The development migration ledger contains 172 entries.
- The recovered foundations cover payer, communication automation, pathology, medicines and missing staff enum values. They were reconstructed from the connected project's schema catalog without copying patient data or secrets.
- This replay is evidence of executable migration order, not a complete schema/data equivalence or backup-restore test. The connector-assigned ledger versions require reconciliation with the repository's filename versions before a future CLI-driven deployment.

## Synthetic isolation checks

Tests ran inside SQL transactions with `ROLLBACK`, using two invented practice IDs and `example.invalid` auth users. The repeatable script is `integration/practice-configuration/isolated-db-fixtures.sql`; it passed against the isolated development project. The fixture count after rollback was zero.

| Test | Result |
| --- | --- |
| Practice A manager reads operating configuration and payer relationship for A and B | PASS: only A row visible |
| Practice A manager attempts B operating configuration upsert | PASS: RLS denied mutation |
| Practice A reception role attempts same-practice operating configuration update at AAL2 | PASS: zero rows updated |
| Practice A manager attempts same-practice operating configuration update at AAL1 | PASS: zero rows updated |
| Practice A manager calls simulator for Practice B | PASS: `Practice access required` |
| Practice A manager calls simulator for A with no payer rules | PASS: JSON includes `decision_trace`; no tariff outcome claimed |
| Practice A manager inserts own operating configuration at AAL2 | PASS: the tenant-scoped `INSERT` audit event records the synthetic actor |
| Two active synthetic tariff versions: 0190 at R1,146 through 2026-12-31 and R1,210 from 2027-01-01 | PASS: 2026-12-15 and 2027-01-15 simulations returned the respective expected scheme amounts, version numbers and effective-date provenance |
| Draft policy submitted and approved, then activated before Operations execution exists | PASS: activation refused by the policy version guard |

All four new configuration tables have RLS enabled in the development catalog. The audit-event table has one read policy; mutations run through the guarded trigger/function path.

These checks do not cover nine-role browser UAT, same-rank rule conflict, storage access, or every privileged RPC. The simulator remains a thin explanation layer over the existing resolver; Effective Rules V2 still has to prove conflict handling and the full contractual calculation across more complex cases.

## Application checks

At branch commit `037e75e` (with the audit notes still uncommitted at the time of this record): TypeScript, 16 auth tests, 20 clinical/coding tests, 77 literal internal links, 162 recorded migration checksum checks, and a Next.js production build passed. The build required harmless local `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` placeholder values for prerendering; it did not test live Supabase connectivity.

## Open gates

1. Preview environment credentials have not been proven to target the development project. Vercel's currently listed production deployment is main `2adc0e4`; no feature branch preview was deployed.
2. Clinical narrative RLS, pathology, medicines, patient documents, private file policies and security-definer functions still need the coordinated privacy alignment documented in `CLINICAL_PRIVACY_DEPENDENCY_INVENTORY_2026-09-27.md`.
3. A full role/tenant matrix, conflict and more complex tariff fixtures, browser/mobile accessibility UAT, schema diff and generated database types remain outstanding.
4. Production promotion, recovery testing, monitoring and incident response evidence remain separate release gates.
