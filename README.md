# PracticeCtrl

PracticeCtrl is a multi-tenant clinical operations, coding, billing and revenue workspace. The app uses Next.js 15, Supabase Auth and Postgres. Dr Tembisa Tini Inc is a staging tenant; the interface does not imply production clinical or claims readiness.

## Local checks

Use Node 22 and `npm ci`. Configure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` for a Supabase project you are authorised to use. Never put a service-role or secret key in a `NEXT_PUBLIC_` variable.

Copy `.env.example` to `.env.local` and replace both values with the publishable connection for an isolated nonproduction Supabase environment before interactive testing. The example values only let a local compilation run; they cannot authenticate or validate tenant workflows. `npm run build` evaluates static routes and requires syntactically valid public Supabase configuration.

| Command | Purpose |
| --- | --- |
| `npm run typecheck` | TypeScript check for the app |
| `npm run test:clinical` | Clinical coding regression tests |
| `npm run test:security` | Authentication redirect checks |
| `npm run audit:links` | Verify literal internal links against app routes |
| `npm run build` | Production Next.js build |

The link audit covers literal paths in JSX, navigation data, and router calls. Computed URLs, data-driven destinations, external integrations, and authenticated journeys require separate review.

## Security boundaries

Authenticated staff pages resolve the active tenant and require MFA assurance level 2 in `lib/auth/server.ts`. Database RLS and governed RPCs enforce data access and mutations. Public account recovery uses Supabase's default reset email; the callback accepts only same-origin return destinations. Never use real patient data for controlled staging UAT.

Release readiness lives at `/admin/readiness` for authorised roles. CI and a successful deployment alone do not satisfy the release gate; the registered staging origin, health evidence, stored release probe, source licences, and controlled UAT are tracked separately.

The Finance role is a same-practice financial oversight and recovery role, not a transactional billing or claims role. The authoritative capability decision and its current UAT requirements are in [the Finance access contract](docs/FINANCE_ACCESS_CONTRACT_2026-09-24.md); its staging RLS migration source is [FINANCE_READ_RLS_20260924.sql](docs/FINANCE_READ_RLS_20260924.sql).

## Appointment source of truth

The existing PMS owns the appointment diary, its times, rescheduling and cancellations. PracticeCtrl owns the request queue, contact and follow-up, and the auditable record that a request was confirmed in the PMS. Staff must book in the PMS and enter its appointment reference before marking a request `Confirmed in PMS`. A requested date is only a preference. The `/appointments` page presents the handoff and any historical PracticeCtrl bookings as read-only records; it is not a second diary.

The controlled staging database applied `pms_diary_source_of_truth_20260924` and `pms_diary_policy_tuning_20260924`, whose consolidated SQL is in `docs/PMS_DIARY_BOUNDARY.sql`. The change revokes direct PracticeCtrl appointment creation and rescheduling, requires a PMS reference for confirmation, and writes an appointment-request event. Before applying this change to another database, reconcile any existing local appointments and `Booked in PracticeCtrl` requests against the PMS. A future PMS integration must add explicit identity matching, reconciliation, idempotency and an audit trail before replacing this manual handoff.

## Current release assessment

See the [executive pre-launch scorecard](docs/PRACTICECTRL_EXECUTIVE_PRELAUNCH_SCORECARD_2026-09-24.md) for the release decision and the [full pre-launch audit](docs/PRELAUNCH_AUDIT_2026-09-24.md) for its supporting evidence. The staging tenant has no patient or appointment transactions yet; passing builds and a READY deployment of an older commit do not establish production readiness.
