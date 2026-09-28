# Role and tenant UAT runbook

**Purpose:** Turn the Finance access remediation into release evidence without using patient data.
**Environment:** Controlled staging only.
**Release status:** Required before production promotion.

## Preconditions

1. Deploy the audited branch that contains `finance_read_access_alignment_v034` UI changes.
2. Create two controlled test practices, **Practice A** and **Practice B**, with no real patient, invoice, claim or contact data.
3. Create one active MFA-enrolled test identity for each staff role in Practice A. Create a separate active test identity in Practice B.
4. Use unique, traceable test prefixes (for example `UAT-A-20260924-*`) for every record.
5. Capture the tester, timestamp, role, practice, route, expected result, actual result, request ID/audit event ID and screenshot for every case.
6. Delete or deactivate the controlled test identities and fixtures after sign-off, following the documented retention decision.

## Required identities

| Identity | Practice | Role | MFA | Purpose |
| --- | --- | --- | --- | --- |
| `uat-a-system-admin` | A | System admin | AAL2 | Full privileged control and evidence capture |
| `uat-a-practice-manager` | A | Practice manager | AAL2 | Delegated operational and financial control |
| `uat-a-reception` | A | Reception | AAL2 | Requests and PMS confirmation |
| `uat-a-practitioner` | A | Practitioner | AAL2 | Clinical-only confirmation boundary |
| `uat-a-billing` | A | Billing | AAL2 | Billing, claims and import control |
| `uat-a-finance` | A | Finance | AAL2 | Financial read, liability and recovery boundary |
| `uat-a-coder` | A | Coder | AAL2 | Coding/recovery review boundary |
| `uat-a-clinical-admin` | A | Clinical admin | AAL2 | Clinical administration boundary |
| `uat-a-auditor` | A | Auditor | AAL2 | Read-only audit boundary |
| `uat-b-control` | B | System admin or Finance | AAL2 | Cross-tenant negative control |

Do not reuse a real staff address. Do not grant one UAT identity memberships in both practices except for a separately documented practice-switching test.

## Core negative-access matrix

| Test | Expected result |
| --- | --- |
| Any Practice A role requests a Practice B route or record ID | No data returned; no mutation; no information leak in error text |
| Inactive membership attempts any staff route | Sign-in may succeed, but staff context and protected data are denied |
| Auditor attempts a mutation | Control absent or disabled; direct request/RPC rejected; audit record retained where applicable |
| Reception, practitioner, coder or clinical admin opens a finance-only route | Access denied or route contains no protected finance data |
| Finance attempts invoice creation, receipt posting/allocation, claim preparation/authorisation, remittance matching, variance resolution, or import staging/promotion | Control absent; direct RPC/function call is rejected by role policy |
| Finance reads billing, claims, source snapshot, report and import-history routes in Practice A | Same-practice records are visible and no controls are offered for excluded mutations |
| Finance resolves liability and records a recovery action | AAL2 is required; successful action writes the expected audit/evidence record |
| Billing performs approved financial mutations | AAL2 and governed validation are required; event/audit trail is recorded |

## Workflow evidence

### Requests → PMS handoff

1. As Reception, create a request using a controlled patient fixture.
2. Record the appointment in the external PMS, not PracticeCtrl.
3. Return to PracticeCtrl and confirm the request with the PMS reference.
4. Verify the request event records the PMS reference and actor.
5. Verify that no local PracticeCtrl appointment is created or rescheduled.

### Finance boundary

1. As Billing, create a controlled draft invoice and one claim fixture if the governed prerequisites are available.
2. As Finance, verify the Billing, Claims & ERA, Revenue Integrity, Revenue Control, reports and VeriClaim import-history screens show only Practice A data.
3. Verify the Finance UI describes the correct read-only boundary and has no buttons/forms for excluded actions.
4. Attempt each excluded direct action through the browser/network client. Record the returned role error and confirm no data changed.
5. As Finance with AAL2, resolve a controlled revenue-liability case and record a controlled recovery action. Verify the resulting audit and evidence rows.

### Cross-tenant control

1. Capture a known Practice B record identifier.
2. While signed in as every Practice A test identity, request the matching route/API path and attempt an allowed-looking mutation against that identifier.
3. Verify zero rows, no changed timestamps and no leaked names, amounts, identifiers or file metadata.
4. Repeat the test in the opposite direction for the Practice B control identity.

## Release evidence checklist

- [ ] Branch deployed to the exact registered staging origin
- [ ] All ten UAT identities sign in and complete MFA
- [ ] All nine Practice A role rows completed
- [ ] Finance allow/deny matrix completed
- [ ] Cross-tenant negative checks completed in both directions
- [ ] Request → PMS confirmation evidence captured
- [ ] Revenue/recovery action and audit evidence captured
- [ ] Failed mutations prove no record changed
- [ ] Results entered into release validation/probe records
- [ ] Evidence reviewed and signed by the designated release owner

This runbook is intentionally stricter than a code review. Passing it does not replace backup restoration, monitoring, authentication-recovery and performance gates.
