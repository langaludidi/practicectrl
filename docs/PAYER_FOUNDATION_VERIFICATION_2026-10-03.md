# Payer foundation verification — 3 October 2026

## Scope

The recovered payer foundation was exercised against the isolated **PracticeCtrl Development** Supabase project using synthetic, rollback-only fixtures.

Verified path:

1. create a synthetic practice and authorised practice manager;
2. create a synthetic medical scheme;
3. create an active practice payer contract and effective tariff rule;
4. link a draft invoice to the selected payer contract;
5. simulate the contract payment for the service date;
6. preview invoice-line payer resolution;
7. record the governed payer resolution;
8. verify expected scheme amount, patient liability and rule/contract provenance;
9. roll all test data back.

## Defects found and repaired

### Missing invoice payer-contract link

The recovered `preview_invoice_line_payer_resolution` function referenced `billing_invoice.payer_contract_id`, but that column had not been recovered into the development schema.

Repair:
- added nullable `billing_invoice.payer_contract_id`;
- added FK to `payer_contract`;
- added an index;
- added same-practice tenant guard.

### Payer resolution could not update invoice lines

`record_invoice_line_payer_resolution` is a governed SECURITY INVOKER RPC. The recovered database granted no authenticated UPDATE path on `billing_invoice_line`, so the function could not lock/update the line.

Repair:
- added an UPDATE grant protected by a transaction-local mutation guard;
- added an UPDATE RLS policy requiring AAL2, an authorised finance/management role, draft invoice state and the governed mutation guard;
- updated the RPC to enable the guard before the line lock/update.

### Payer resolution could not insert provenance

`payer_rule_resolution` allowed staff reads but had no authenticated INSERT path, so the governed RPC could not persist the resolution record.

Repair:
- added INSERT grant;
- added insert RLS requiring AAL2, same-practice authorised role, `resolved_by=auth.uid()` and a transaction-local payer-resolution mutation guard;
- updated the RPC to raise the guard only for the controlled insert.

## Result

The synthetic payer-resolution fixture now passes end-to-end and rolls back cleanly.

Verified values in the fixture:

- charged amount: R1,450;
- effective contractual/scheme amount: R1,146;
- estimated patient liability: R304;
- applied contract and rule provenance persisted correctly.

## Remaining payer gates

This test verifies the recovered contract/rule resolution spine. It does **not** yet sign off the complete production claim path.

Still required:

- full claim-preflight fixture using a governed licensed SAMA CCSA code;
- active verified patient scheme membership;
- authorisation/referral requirements where applicable;
- claim preparation/submission readiness;
- cross-tenant and role-negative tests around payer RPCs;
- remittance/adjudication integration and variance creation.

Production promotion remains blocked until those gates and the wider role/privacy UAT are complete.
