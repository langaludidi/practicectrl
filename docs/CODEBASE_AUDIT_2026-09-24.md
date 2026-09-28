# PracticeCtrl codebase audit — 24 September 2026

Scope: the Next.js repository at `2adc0e4`, the registered staging tenant, the supplied signed-in dashboard and billing screenshots, and read-only Supabase policy/function inspection. Authenticated browser journeys were not replayed with a user's private session. The review covers route existence, principal auth boundaries, the billing example, file hygiene, and the build; it does not certify every clinical workflow or a production release.

## Fixed in this branch

| Area | Evidence | Change |
| --- | --- | --- |
| Auth callback | `/\\evil.example` passes the old leading-slash check and resolves off origin using `new URL` | Resolve destinations on the request origin and fall back to `/dashboard` when external; add regression cases |
| Session UX | Signed-in shell had no sign-out action | Add an accessible sign-out button using Supabase Auth |
| Platform MFA | `/mfa?next=/platform/tenants` always sent users to `/dashboard` | Respect only that known platform destination for platform roles |
| Billing invoice | `create_practice_custom_invoice` explicitly requires a patient; UI offered “No patient link” | Require selection and explain empty state |
| Billing receipt | `create_billing_receipt` requires a patient or scheme; the UI supplied neither when “No patient link” was selected, and offered other payer types although it always passed a null scheme | Require a patient and describe this form as patient receipt only |
| Billing split | Empty patient portion defaulted to full total even when a scheme portion was entered | Derive patient portion from the remainder and validate the sum before RPC |
| Finance access | Finance had transaction controls in the UI while its financial reads were incomplete under RLS | Define a least-privilege contract, remove Finance billing/claim/import mutations, keep its governed AAL2 revenue/recovery actions, and align 18 same-practice read policies |
| Navigation | “Reports” pointed to `/analytics`, while the report catalogue is `/reports` | Route Reports to the catalogue and add a separate Analytics entry; give the collapsed rail distinct module icons |
| Billing accessibility | Fields relied on placeholder text, the draft-line form showed an empty select when no drafts existed | Add persistent labels and a specific empty state |
| Repository | `compose:sql` and `verify:source` referenced absent files; generated TypeScript cache was tracked | Remove dead scripts; untrack/ignore `*.tsbuildinfo`; document supported commands |
| Links | Literal links had no automated route check | Add `audit:links` to CI; it currently checks 72 literal paths against 50 routes |

## Open findings

1. **Finance access implementation is aligned, but release evidence remains incomplete.** `canManageBilling` now excludes Finance, while the separate revenue-control and recovery capabilities retain its governed AAL2 role. Claims, Revenue Integrity and import staging controls are read-only for Finance. Staging migration `finance_read_access_alignment_v034` adds Finance to 18 existing same-practice read policies; structural verification found 18/18 policies retain active membership and tenant predicates, with zero Finance write policies across the affected tables. The current Vercel frontend is still older than this branch, and Finance/browser/cross-tenant UAT remains required before closing the release gate. See `FINANCE_ACCESS_CONTRACT_2026-09-24.md` and `ROLE_AND_TENANT_UAT_RUNBOOK_2026-09-24.md`.
2. **Controlled staging evidence.** The first admin invitation is accepted and a verified MFA factor exists. The exact origin is registered, but at audit time there was no `release_probe_snapshot`, `release_validation_run`, or `release_artifact_evidence` for `0.34.0-dev.1`. The deployed health route could not be independently reached through Vercel protection from the audit client; a protected redirect is not a passed health check. Do not promote on the basis of CI or a visible dashboard alone.
3. **UI colour migration.** `docs/UI_UX_SYSTEM.md` specifies navy and teal, but the repository contains about 200 references to the older plum `#4a1f3e`. Billing actions in this branch were aligned with the current system. The remainder should be migrated by component group with screenshot review to avoid unintended status/contrast changes.
4. **Link coverage.** The static check finds no missing literal route today, but computed destinations, role-gated screens, data-driven report links, external links and redirect behavior need authenticated browser UAT.
5. **Accessibility coverage.** The billing form has labels after this change. Keyboard order, focus return after navigation, screen reader labels across the other workspaces, and mobile overlays still require browser-based testing. A screenshot alone does not establish compliance.
6. **Other payer receipts.** The Billing UI previously exposed scheme and other payer types without providing a matching scheme/account selector. The patient form now names its actual scope; a separately designed and authorized workflow is needed before enabling other payer receipts.

## Continued local build

- Align MFA, first-administrator bootstrap and invitation acceptance with the approved navy/teal controls.
- Give receipt allocation persistent field labels and a prerequisite explanation when there are no receipts or outstanding invoices.
- Surface billing query failures with a retryable route error state instead of displaying them as empty invoice and receipt lists. The Finance role still requires browser and cross-tenant integration checks after deployment.
- Recover the sign-in form after unexpected request failures, and validate finite positive amounts in patient receipt and invoice entry.
- Turn the header's patient-directory shortcut into an honest “Find patients” action and add a practice-scoped patient-name search. The first 500 results are shown; wider clinical record search remains separate work.

## Verification

- TypeScript, 20 clinical tests, and 16 auth/role-contract tests passed locally.
- Production Next.js build passed with placeholder public Supabase build configuration.
- Static link audit passed on 72 literal internal links.
- The live release gate remains fail-closed pending recorded health, probe, and controlled UAT evidence.
