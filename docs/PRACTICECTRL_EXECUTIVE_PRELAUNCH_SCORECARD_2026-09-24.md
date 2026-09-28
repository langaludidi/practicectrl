# PracticeCtrl Pre-Launch Audit Scorecard

**Audit date:** 24 September 2026  
**Environment:** Staging  
**Auditor status:** Controlled staging assessment  
**Release recommendation:** ❌ Not production ready

## Executive risk rating

| Area | Score | Status |
| --- | ---: | --- |
| Functionality | 40% | 🔴 High risk |
| User experience | 8% | 🔴 High risk |
| Security | 31% | 🔴 High risk |
| Data integrity and recovery | 13% | 🔴 High risk |
| Permissions and access control | 0% | 🔴 Critical |
| Error handling | 25% | 🔴 High risk |
| Performance and scale | 0% | 🔴 Critical |
| Hosting and deployment | 29% | 🔴 High risk |
| Monitoring and observability | 0% | 🔴 Critical |
| Documentation | 17% | 🔴 High risk |
| Business alignment | 20% | 🔴 High risk |
| **Overall verified coverage** | **19%** | **🔴 Not ready** |

The 19% figure measures verified audit coverage against the release checklist. It is not a code-quality score.

## Critical release blockers

### P1. Finance access model — implementation complete, release verification pending

**Severity:** Critical  
**Status:** ⚠️ Remediated in the audit branch and controlled staging; still a release gate pending deployment and UAT

Finance is now defined as a same-practice financial-read, revenue-control and recovery role, rather than a transactional billing or claims role. The audit branch removes Finance billing/claim/import mutations, adds the necessary read-only UI states, and staging migration `finance_read_access_alignment_v034` aligns 18 existing financial `SELECT` policies. Structural verification found all 18 policies retain active same-practice membership predicates and no Finance write policy was introduced in the affected financial tables.

The current Vercel frontend is still older than the audit branch, and controlled Finance/browser/cross-tenant tests have not yet been executed. The release gate remains closed until that evidence exists.

### P2. No role-based UAT evidence

**Severity:** Critical  
**Status:** ❌ Release blocker

Nine operational roles exist, but there is no verified sign-in and workflow evidence across each role or cross-tenant negative testing.

**Impact:** The permission model remains unproven.

### P3. Backup restore not proven

**Severity:** Critical  
**Status:** ❌ Release blocker

Backup capability, restoration, and recovery objectives have not been demonstrated.

**Impact:** Business continuity risk after data loss or an environment failure.

### P4. Monitoring and alerting not verified

**Severity:** Critical  
**Status:** ❌ Release blocker

There is no evidence of working uptime checks, alert routing, resource thresholds, or alert delivery.

**Impact:** Failures could occur without timely detection or response.

### P5. Current branch not deployed

**Severity:** Critical  
**Status:** ❌ Release blocker

Staging serves commit `2adc0e4`, while the audited branch contains commit `4e9e6e9`. The reviewed platform is therefore different from the deployed platform.

**Impact:** Existing audit evidence cannot support a production release.

## Major findings

### Security

| Finding | Status |
| --- | --- |
| Dependency vulnerabilities resolved | ✅ |
| Public service-key exposure not identified | ✅ |
| HTTPS enabled | ✅ |
| Appointment ownership model enforced | ✅ |
| Leaked-password protection | ❌ Disabled |
| Penetration-test evidence | ⚠️ Not available |
| MFA recovery validation | ⚠️ Not available |
| Documented lockout policy | ⚠️ Not available |

### Data governance

| Finding | Status |
| --- | --- |
| PMS appointment ownership boundary defined | ✅ |
| Local appointment creation disabled | ✅ |
| Data lifecycle documented | ⚠️ Incomplete |
| Backup retention verified | ⚠️ Not verified |
| Restore capability proven | ❌ |
| Disaster recovery proven | ❌ |

### User experience

| Finding | Status |
| --- | --- |
| PMS reference validation implemented | ✅ |
| Mobile testing | ⚠️ Not evidenced |
| Accessibility audit | ⚠️ Not evidenced |
| Keyboard navigation | ⚠️ Not tested |
| Screen-reader validation | ⚠️ Not tested |
| Success and error message inventory | ⚠️ Incomplete |

### Operations

| Finding | Status |
| --- | --- |
| CI build pipeline active | ✅ |
| TypeScript verification passes | ✅ |
| Automated tests pass | ✅ |
| Dependency audit passes | ✅ |
| Rollback process documented | ⚠️ No |
| Production promotion process complete | ⚠️ No |
| Release validation evidence | ❌ No |

## Production readiness assessment

| Category | Result |
| --- | --- |
| Security ready | ❌ No |
| Operationally ready | ❌ No |
| Recoverable after failure | ❌ No |
| Permission model verified | ❌ No |
| Role UAT complete | ❌ No |
| Monitoring ready | ❌ No |
| Deployment ready | ❌ No |
| Business workflow verified | ❌ No |

## Required go-live gates

1. **Access model:** Deploy the aligned Finance UI, execute negative-access tests, and verify all nine operational roles using the documented two-practice UAT runbook.
2. **Staging validation:** Deploy the audited branch, complete the request → PMS confirmation workflow, and capture audit-event evidence.
3. **Resilience:** Perform a backup restore exercise, define RPO and RTO, and document the disaster-recovery procedure.
4. **Observability:** Configure monitoring and alert routing, then verify delivery with a controlled test.
5. **Security:** Enable leaked-password protection, validate MFA recovery, and test authentication and session controls.

## Auditor's verdict

**Readiness level:** 19% verified coverage  
**Release decision:** ❌ Reject production promotion  
**Confidence level:** High

The PMS ownership boundary is enforced and the legacy local booking model is technically disabled. The Finance access implementation is now structurally aligned, but PracticeCtrl cannot be certified for production until its deployment and role-based UAT, monitoring, backup recovery, deployment validation, and operational readiness are demonstrated.

**Overall status: RED — do not release.**

## Evidence

See [the detailed pre-launch audit](PRELAUNCH_AUDIT_2026-09-24.md) for the tested commands, code and database evidence, remediation work, and outstanding verification steps.
