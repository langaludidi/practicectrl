# Finance access contract

**Decision date:** 24 September 2026
**Scope:** PracticeCtrl staff role `finance`
**Status:** Implemented in the audit branch and staging RLS; deployment and role-based UAT remain required before release.

## Decision

Finance is a financial oversight and recovery role. It may review same-practice financial records and reports, resolve revenue liability, and record recovery actions. It is not a transactional billing or claims role.

This is deliberately enforced in both layers:

- The interface hides transactional controls for Finance.
- RLS grants Finance same-practice `SELECT` access to the financial records used by its screens and reports.
- No Finance `INSERT`, `UPDATE`, or `DELETE` policy is added for core billing, claim, remittance, quote, or VeriClaim import records.
- Governed revenue-control and recovery RPCs continue to require an active Finance membership and MFA assurance level 2.

## Finance capability boundary

| Area | Finance access | Explicitly excluded |
| --- | --- | --- |
| Billing | Read invoices, lines, receipts, allocations, credits, quotes and ledger records | Create/finalise invoices, change lines, post/allocate receipts, issue credits or edit quotes |
| Claims and ERA | Read claims, claim lines, remittances and variances | Run/persist claim pre-flight, prepare a claim, authorise submission, match remittances or resolve variances |
| Revenue integrity | Read the exception queue and follow resolution links | Reassess, prepare, or continue a claim |
| Revenue control | Resolve liability and collection suppression through the governed AAL2 RPC | Direct financial transaction changes |
| Recovery | Record recovery actions through the governed AAL2 RPC | Bypass liability, suppression, evidence or audit controls |
| Payer contracts | Read contracts and governed references | Create, review, approve or activate contract versions |
| VeriClaim imports | Read batch history and promoted source evidence | Upload, stage or promote source files |
| Reports | Run permitted financial reports | Gain write access through a report route |

## Financial role matrix

This matrix is the current application contract for the financial modules. “Read” does not bypass table-level tenancy checks.

| Role | Financial read | Billing and claim transactions | Revenue control | Recovery actions | VeriClaim import |
| --- | --- | --- | --- | --- | --- |
| Practitioner | No | No | No | No | No |
| Reception | No | No | No | No | No |
| Billing | Yes | Yes | Yes | Yes | Stage/promote |
| Finance | Yes | No | Yes, AAL2 | Yes, AAL2 | Read only |
| Coder | No | No | No | Coding-review recovery path only | No |
| Practice manager | Yes | Yes | Yes | Yes | Stage/promote |
| Clinical admin | No | No | No | No | No |
| Auditor | Yes | No | No | No | Read only |
| System admin | Yes | Yes | Yes | Yes | Stage/promote |

The matrix is tested by `integration/auth/tests/financial-access.test.ts`. It is an automated source-contract test, not evidence that each user journey has been executed in a browser.

## RLS scope

`FINANCE_READ_RLS_20260924.sql` adjusts eighteen pre-existing read policies. Each policy retains an active `practice_staff_member` requirement and a same-practice join or predicate. It adds `finance` to the existing financial-reader set:

`billing`, `finance`, `practice_manager`, `system_admin`, `auditor`.

No membership, tenant predicate, policy role, write policy, function privilege, or service credential is broadened by this change. The migration uses `ALTER POLICY ... USING (...)`; it does not create a permissive catch-all policy.

## Required validation before release

1. Deploy the audit branch to the controlled staging origin.
2. Create controlled test identities for all nine roles in two separate practices, using no patient data.
3. Run the Finance read-only and revenue/recovery journeys, then assert that Finance receives a policy failure for every excluded mutation.
4. Run cross-tenant negative queries and page-access checks for every role.
5. Store screenshots, audit-event IDs and timestamped results in the release probe before changing the release decision.

Until those checks are complete, the platform remains **RED — do not release**.
