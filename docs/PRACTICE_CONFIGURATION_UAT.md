# Practice Configuration V1: isolated environment acceptance

Run against a separate Supabase project with the reconciled baseline schema and this branch's migrations. Do not run against the connected first-admin staging tenant. Use synthetic practices A and B and synthetic staff accounts with MFA. Record query outputs, screenshots, deployment SHA and role for each case.

| Case | Actor and action | Expected evidence |
| --- | --- | --- |
| Tenant read | Practice A manager reads Practice B `practice_payer_relationship`, `practice_policy`, `practice_operating_config`, `practice_configuration_event` | Empty/denied for all; A records visible |
| Tenant write | Practice A manager inserts/updates a B payer relationship or policy | RLS rejection, B record unchanged, no B audit event |
| Role write | A reception, billing, finance or auditor tries identity RPC and policy insert | Denied; A administrator with AAL2 can save |
| MFA | A manager at AAL1 tries identity RPC, relationship insert and operating config upsert | All denied |
| Immutable rule | Approve a policy version then alter its title, effective date or owner | Rejected; new version required |
| Policy safety | Approve a policy and attempt `active` | Rejected until Operations enforcement is implemented |
| Payer lifecycle | Submit, approve, activate relationship v1; prepare v2 while v1 active; retire v1 then activate v2 | No simultaneous active versions; audit identifies actor and transition |
| Branding safety | Save an invalid logo URL or timezone | Rejected; prior identity remains intact |
| Historic simulator | Simulate tariff on 2026-12-15, then 2027-01-15 with separate approved dated rules | Correct effective rule version, amount, source and contract trace for each date |
| Rule conflict | Two same-ranked effective tariff rules both match | **Expected Rules V2 behaviour:** review required, no silent winner. Currently unimplemented release blocker. |
| PMS ownership | Save operating defaults and appointment type; attempt local booking/rescheduling | Defaults persist; local appointment mutation remains denied; requests require PMS reference |
| Change audit | Update identity, location, billing footer, practitioner and operating config | Visible tenant-scoped history with before/after; banking details never logged |
| Browser | Desktop, tablet and narrow mobile; keyboard tab through forms; submit errors | No clipped controls or horizontal overflow; accessible labels and feedback |

Run `npm ci`, `npm run typecheck`, `npm run test:security`, `npm run test:clinical`, `npm run audit:links`, `npm run build` under Node 22. Record the exact Git SHA, Supabase migration versions and preview deployment URL. No V1 completion or production sign-off until these cases and a human walkthrough pass.
