# PracticeCtrl prelaunch audit — 24 September 2026

## Executive scorecard

The concise release sign-off is in the [PracticeCtrl Pre-Launch Audit Scorecard](PRACTICECTRL_EXECUTIVE_PRELAUNCH_SCORECARD_2026-09-24.md). This report provides the detailed evidence behind that decision.

**Decision:** The PMS owns appointment times and diary changes. PracticeCtrl owns requests, follow-up, the PMS confirmation reference and its audit event. See `README.md` and `PMS_DIARY_BOUNDARY.sql`.

**Release decision: ❌ Not production ready.** This is a controlled staging assessment, not a production certificate. The staging database contains zero patients, requests, local appointments, invoices and claims. No authenticated end-to-end journey was exercised in this run. The READY Vercel deployment is from commit `2adc0e4`; this local branch and its revised interface are not deployed.

**Rating:** ✅ Verified pass; ⚠️ needs improvement or lacks required test evidence; ❌ known failure or missing release gate; N/A genuinely inapplicable. The summary's score is *verified pass coverage* (✅ / applicable checklist items), not a subjective quality estimate. An untested item receives no credit; N/A is excluded. This conservative measure avoids claiming readiness from static inspection.

## Post-audit remediation update — Finance access

The point-in-time assessment below correctly recorded a Finance UI/RLS mismatch. That implementation defect has now been remediated in the audit branch and controlled staging:

- `finance` has financial read access plus the existing AAL2-governed revenue-control and recovery actions; it has no transactional billing, claim, remittance or import mutation capability.
- Staging migration `finance_read_access_alignment_v034` changes 18 pre-existing financial read policies. Structural verification confirms 18/18 policies include Finance, retain active same-practice membership predicates, and the affected tables have zero Finance write policies.
- The interface gates Claim submission, Revenue Integrity and VeriClaim import actions, while retaining a clear Finance read-only state. Financial report catalogue entries are explicitly read-only for Finance.
- `integration/auth/tests/financial-access.test.ts` covers the nine-role source contract. TypeScript, 20 clinical tests, 16 authentication/role-contract tests and the 74-link audit pass locally.

This does **not** complete role-based UAT, cross-tenant negative testing or deployment validation. Therefore the audit score remains 19% verified coverage and the release decision remains RED. The required test procedure is [ROLE_AND_TENANT_UAT_RUNBOOK_2026-09-24.md](ROLE_AND_TENANT_UAT_RUNBOOK_2026-09-24.md).

## 1. Feature and functionality

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| All active features documented | ⚠️ | README is a short overview; no complete versioned feature register. |
| Unused features identified | ⚠️ | Old booking setup/workspace removed from current branch; other modules need ownership review. |
| Deprecated features removed | ✅ | Direct diary booking and local setup components removed from active code. |
| Duplicate functionality removed | ✅ | Requests and appointment page now share one PMS handoff; no local booking UI. |
| Feature ownership defined | ✅ | PMS diary boundary documented; PracticeCtrl records request and confirmation. |
| Every core process tested | ❌ | No patient, claims, billing or clinical transaction UAT; staging has no such records. |
| All user journeys completed | ⚠️ | Authenticated multi-role UAT unavailable; code trace is not a completed journey. |
| No broken links | ✅ | `npm run audit:links` passed 74 literal internal links against 50 routes. Dynamic and external links remain unverified. |
| No dead-end screens | ⚠️ | Authenticated role screens have not been navigated end to end. Audit viewer still claims activation pending. |
| Appropriate success messages | ⚠️ | PMS request action acknowledges saving; broader success-state inventory not checked in browser. |

## 2. User experience

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Navigation intuitive and menus consistent | ⚠️ | Static links resolve; actual desktop/mobile journeys not observed this run. |
| Search functions correctly | ⚠️ | Patient search exists; no authenticated result test. |
| Breadcrumbs where applicable | ⚠️ | Route hierarchy exists; breadcrumb behavior not established. |
| Required fields validated | ✅ | PMS reference required in form, RPC and database constraint. Remaining forms need a sweep. |
| Friendly errors and confirmations | ⚠️ | Request errors surfaced; several screens still expose raw RPC messages. |
| Duplicate form submissions prevented | ⚠️ | Request action disables during save; network/retry behavior untested. |
| Mobile and tablet layout | ⚠️ | Responsive classes exist; no current-run device screenshots or interaction evidence. |
| Touch targets, readability and horizontal overflow | ⚠️ | Tables scroll locally; no device/browser measurements. |
| Keyboard navigation | ⚠️ | Not tested with keyboard. |
| Colour contrast | ⚠️ | Navy/teal tokens coexist with older plum; no measured contrast audit. |
| Persistent labels | ⚠️ | PMS form labels added; other workspaces still rely on placeholders. |
| Screen reader interpretation | ⚠️ | Not tested with assistive technology. |

## 3. Security

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Login | ✅ | User previously confirmed successful staging sign-in; authenticated replay not performed in this run. |
| Password reset and lost-device MFA recovery | ⚠️ | Recovery route exists; reset delivery and lost-factor recovery need live tests. |
| Session timeout and lockout controls | ⚠️ | No documented, verified timeout/lockout policy. |
| User permissions documented | ⚠️ | Finance contract and automated source checks now exist; comprehensive role documentation and browser evidence are still incomplete. |
| Role matrix and cross-tenant access | ❌ | Finance implementation is aligned, but no negative tests across all nine roles and two tenants have been executed. |
| Administrative functions restricted | ⚠️ | AAL2 and role guards exist; all admin paths have not been tested negatively. |
| HTTPS and TLS | ✅ | Staging Vercel URL uses HTTPS; certificate chain/expiry not independently checked. |
| Sensitive data encryption and key handling | ⚠️ | Supabase managed services in use; encryption and retention evidence not collected. |
| Secrets outside source and client API key scope | ✅ | Only publishable key is in CI/Vercel config; no service key found in public-client config. Audit of all deployment secrets remains pending. |
| Dependency vulnerabilities | ✅ | After pinning PostCSS 8.5.28, Sharp 0.35.4 and Vitest 5.0.1, the full `npm audit --audit-level=moderate` reports zero known vulnerabilities. The CI workflow now enforces this gate. |
| SQL injection and XSS | ⚠️ | Supabase parameterized client/RPC calls and React escaping used; no dedicated adversarial penetration test. |
| File upload security | ⚠️ | Governed upload path exists, but type, size, content and malware policies need tested evidence. |
| Leaked-password screening | ❌ | Supabase security advisor reports the protection is disabled. [Supabase remediation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). |

## 4. Data integrity and recovery

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Naming conventions and redundant tables | ⚠️ | Many schemas are active; no complete table/entity reconciliation. |
| No duplicate entities | ⚠️ | PMS handoff resolves appointment ownership; other imports and operational entities need review. |
| No orphan records | N/A | Staging has zero patients, requests, appointments, invoices and claims; cannot establish correctness under load. |
| Required fields enforced | ✅ | Confirmed request requires nonblank PMS reference at database level; other tables not exhaustively checked. |
| Validation rules tested | ⚠️ | Schema and RPC inspected; real actor and negative-case mutation tests outstanding. |
| Duplicate prevention | ⚠️ | Existing constraints and intake review exist; race/retry tests outstanding. |
| Automated backups and retention | ⚠️ | No backup schedule or retention evidence supplied by connected tools. |
| Restore exercise | ❌ | No documented tested restore. |
| Disaster recovery plan | ❌ | No plan with RPO/RTO, responsibilities or exercise record. |

## 5. Permissions

| Function | System admin | Practice manager | Reception | Practitioner | Billing | Finance | Coder | Auditor | Verified |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Read patient directory | RLS active staff | RLS active staff | RLS active staff | RLS active staff | RLS active staff | RLS active staff | RLS active staff | RLS active staff | ⚠️ Privacy scope needs approval |
| Manage appointment request | Allowed | Allowed | Allowed | Denied | Denied | Denied | Denied | Denied | ⚠️ Code/policy checked; live identities untested |
| Confirm PMS reference | Allowed | Allowed | Allowed | Denied | Denied | Denied | Denied | Denied | ⚠️ RPC/RLS/constraint inspected; no actor UAT |
| Create PracticeCtrl booking | Denied | Denied | Denied | Denied | Denied | Denied | Denied | Denied | ✅ RPC EXECUTE and table INSERT denied |
| View/manage billing | UI allowed | UI allowed | Denied | Denied | UI allowed | **Read only; no transaction controls** | Denied | Some read paths | ⚠️ Source/RLS aligned; browser UAT pending |
| View/manage claims | UI allowed | UI allowed | Denied | Denied | UI allowed | **Read only; no submission/matching controls** | Denied | Some read paths | ⚠️ Source/RLS aligned; browser UAT pending |
| Export and user management | Role guards vary | Role guards vary | Scope varies | Scope varies | Scope varies | Scope varies | Scope varies | Scope varies | ⚠️ Full matrix untested |

The roles above describe inspected code and RLS, not a claim that each was signed in and tested. The generic Admin/Manager/User grid is insufficient for the nine real staff roles.

| Validation item | Rating | Evidence or action |
| --- | --- | --- |
| All permissions tested | ❌ | Nine roles, inactive memberships and cross-tenant cases require dedicated test identities. |
| Escalation paths reviewed | ⚠️ | AAL2 required, but lost-factor administrator recovery and emergency access need exercises. |
| No privilege leaks | ❌ | Broad patient/intake SELECT policies and finance UI mismatch prevent sign-off. |

## 6. Errors and failure recovery

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Invalid input | ✅ | PMS confirmation requires reference in client, RPC and table constraint. |
| Missing data | ✅ | New handoff screen distinguishes zero requests from a failed read. |
| API and database failure | ⚠️ | Request mutations and read errors show feedback; no simulated outage test. |
| Network interruption and retry | ⚠️ | Not tested across client forms. |
| Errors understandable | ⚠️ | Some components show raw database error text. |
| No stack traces exposed | ⚠️ | No external error-path probe. |
| Recovery instructions provided | ⚠️ | Some errors prompt refresh/contact; no product-wide inventory. |
| Logging captures failures | ⚠️ | Hosting/database logs exist, but alert routing and correlation are unverified. |

## 7. Performance and scale

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Page load times | ⚠️ | Build output gives bundles, not real device/network timings. |
| Images and large assets | ⚠️ | Assets present; image optimization and budget not measured. |
| Lazy loading | ⚠️ | Framework code splitting exists; route performance not profiled. |
| Slow queries and API timing | ⚠️ | No representative data or latency measurement. |
| Caching/background jobs | ⚠️ | No workload or queue review. |
| Expected load/capacity | ❌ | No tenant, user, record, traffic targets or tested capacity. |
| Database indexes | ⚠️ | Advisor lists 711 unused indexes in an empty staging workload; deleting them now would be unsound. |

## 8. Hosting and deployment

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Environment documented | ✅ | Vercel Next.js config, Node 22 requirement and publishable Supabase settings in repo. |
| SSL and domain | ⚠️ | HTTPS app URL in use; independent certificate/domain audit pending. |
| Environment variables | ⚠️ | Public variables documented; full server-side configuration inventory missing. |
| Deployment process and rollback | ⚠️ | Vercel Git deployment exists; written rollback/runbook and drill absent. |
| CI pipeline | ✅ | GitHub workflow runs install, dependency audit, typecheck, 25 tests and build on main; local branch is not covered by its main-only trigger. |
| Latest deployed commit | ❌ | READY deployment is `2adc0e4`; current changes are local and not present on staging. |
| Production deployment tested | ❌ | Staging is controlled; release probe/validation/artifact tables all contain zero entries. |

## 9. Monitoring and observability

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Application and error logs | ⚠️ | Platform logs available; retention, access and incident review not evidenced. |
| Audit logs | ⚠️ | New PMS confirmation event policy and RPC installed; no event from an actual workflow yet. Audit page still has a stale activation message. |
| Uptime/performance/database monitors | ⚠️ | No enabled monitor inventory or threshold evidence. |
| Failure/resource/security alerts | ❌ | No configured alert and delivery test available. |

## 10. Documentation

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Architecture | ⚠️ | README covers principal boundaries, but no versioned system/data-flow architecture. |
| Database and API docs | ❌ | Live schema migrations and RPC contract catalogue are not fully mirrored in this repository. |
| Integrations | ⚠️ | VeriClaim/PMS boundary described; provider contracts and failure modes need complete runbooks. |
| Setup guide | ✅ | README specifies Node 22, `npm ci`, env and local checks. |
| Deployment guide | ⚠️ | Vercel config and CI exist, but promote/rollback guide is incomplete. |
| Backup and disaster recovery guide | ❌ | No restore procedure or evidence. |

## 11. Business alignment

| Checklist item | Rating | Evidence or action |
| --- | --- | --- |
| Business rules documented | ⚠️ | PMS appointment boundary now explicit; remaining clinical, billing and payer rules are distributed. |
| Behaviour matches requirements | ⚠️ | Finance UI/RLS implementation is aligned; full clinical workflows and role UAT remain untested. |
| Approval flows and reporting accuracy | ⚠️ | Code paths exist; no representative end-to-end evidence or reconciled report fixtures. |
| Every feature has a business purpose | ⚠️ | Product direction is clear; no feature ownership/retirement register. |
| Low-value features and improvements | ✅ | This audit identifies diary duplication, stale audit screen and inactive setup surfaces for remediation. |

## Summary and release gates

| Area | Verified passes / applicable checks | Score (%) |
| --- | --- | ---: |
| Functionality | 4 / 10 | 40 |
| UX | 1 / 12 | 8 |
| Security | 4 / 13 | 31 |
| Data integrity | 1 / 8 | 13 |
| Permissions | 0 / 3 | 0 |
| Error handling | 2 / 8 | 25 |
| Performance | 0 / 7 | 0 |
| Infrastructure | 2 / 7 | 29 |
| Monitoring | 0 / 4 | 0 |
| Documentation | 1 / 6 | 17 |
| Business alignment | 1 / 5 | 20 |
| **Total verified coverage** | **16 / 83** | **19** |

These numbers measure completed verification, not the fraction of code that works. They will rise when tests and operational evidence are recorded. The known failed controls independently block a production sign-off.

**Top risks:** (1) sensitive-data access has not been proven through cross-tenant and nine-role UAT; (2) backup restore, recovery and operational alerting have no evidence; (3) the new branch is not deployed and release probe/validation evidence is empty.

**Next priority actions:** deploy the aligned Finance UI and execute the two-practice role/tenant UAT; publish the handoff UI and exercise request → PMS confirmation with authorised test identities; prove backup restore, monitoring/alerts and the release probe before production promotion.

## Verification record

- Local `npm ci`, TypeScript, 74 literal links, 20 clinical tests, five auth redirect tests and optimized Next build passed after dependency updates. The build also passed under Node 22.19.0; GitHub CI for the updated branch is still pending because its workflow only triggers on `main`.
- Full `npm audit --audit-level=moderate`: zero known advisories after overriding PostCSS to 8.5.28, Sharp to 0.35.4 and upgrading Vitest to 5.0.1. The lockfile was regenerated and installed; CI gained an audit step.
- Live staging DB: 0 patients, 0 requests, 0 local appointments, 0 invoices, 0 claims. Verified `authenticated` cannot execute the old create/reschedule/status RPCs or insert/update `practice_appointment`. `update_appointment_request_status` remains executable with a PMS-reference constraint and an event policy.
- Supabase security advisor: one warning, [leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Performance advisor: two RLS initialization notices plus 711 unused-index information notices, largely without a real workload.
- Post-audit Finance remediation: controlled staging migration `finance_read_access_alignment_v034` applied successfully. The 18 intended financial reader policies were checked for Finance, active membership and a tenant predicate (18/18 each); the affected core financial tables have zero Finance write policies. The 711 unused-index notices are not a safe deletion signal in an empty staging environment.
- Vercel READY deployment of `2adc0e4` is earlier than this branch. No claim is made that the branch's new screens or dependency fixes are live.
- UI screenshots and login observations from earlier conversations were not reused as fresh visual evidence. Full mobile, accessibility, negative auth and recovery tests require a current authenticated test session.
