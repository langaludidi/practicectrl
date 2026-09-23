# PracticeCtrl report-equivalence matrix

PracticeCtrl does **not** reproduce the legacy VeriClaim report interface. The objective is functional information equivalence through live workspaces, filters, drill-downs, audit trails and governed administration views.

The in-product **Reports** workspace retains the legacy report names as a transition aid and maps each one to its PracticeCtrl equivalent.

## Report families captured from the supplied reference screens

- Favourite Reports → built into the PracticeCtrl Reports workspace.
- Assistant Information → AI & automation governance.
- Batch Mailing → Communications / Recovery communication evidence.
- Billing Templates → billing draft/finalisation exception views.
- Coding Activity → Clinical, Code10, Medicines and Practice Economics.
- Diary Activity → Appointments.
- External Doctors → referring-provider / referral activity.
- Financial Age Analysis → Revenue Control ageing and liability views.
- Financial Generic → Billing, Practice Economics, Revenue Control and Audit.
- Financial Information → Practice Economics.
- Financial Payments (Refunded) → refund/reversal activity.
- Financial Receipts (Received) → receipts, remittance and payment allocations.
- Financial VAT → tax/VAT billing activity where configured.
- Path Labs → Pathology Orders & Results.
- Patients → patient registry and intake.
- Practice Management → Staff & Access, Integration Hub, Source Register and Audit.

## Detailed legacy-name coverage

### Financial Generic
Accounts in Credit; Credit Note Report; Daily Activity Report; Daily Report (Old); Invoice Activity; Invoice Activity for Schemes; Invoice Detail; Invoice Income Activity; Invoice Line Detail; Invoices with Credit Notes not Invoiced Again; Journal Activity; Outstanding Invoices; Pro forma (only) Line Detail; Pro forma Activity; Pro forma’s Not Committed; Scheme Credit Report; Tax Invoice.

### Financial Age Analysis
Age Analysis Combined Scheme & Patient; Only Credit Totals; Only Debit Totals; Sorted by AccNo; Sorted by FileNo; Age Analysis for Patient Liable; Age Analysis for Scheme Liable; Age Analysis summary.

### External Doctors
Invoices From Referring Provider.

### Diary Activity
Diary Bookings.

### Coding Activity
Consultation; Diagnosis Codes (ICD10); Materials (Nappi); Modifier; Procedure.

### Billing Templates
Submitted But Cancelled Billing Templates — by treatment date, provider and service centre; Billing Template But No Invoice — by treatment date, provider and service centre.

### Batch Mailing
Batch Mailing Print Detail; Batch Mailing Status; Legal Notice Detail.

## Product principle

A mapped report is considered available when the underlying information can be reached through a governed PracticeCtrl surface with equivalent or greater operational detail. Where PracticeCtrl has richer source-linked views (for example Practice Economics, Revenue Recovery or Code10), those replace static legacy reports instead of duplicating them.


## Live-backed report tables implemented

The following legacy report families now open through the PracticeCtrl report renderer, with role-gated server queries plus CSV export and print:

- **Financial Age Analysis:** combined scheme/patient, credit-only, debit-only, account-sort, file-sort, patient-liable, scheme-liable and summary.
- **Financial Generic:** Accounts in Credit, Credit Note Report, Invoice Activity, Invoice Activity for Schemes, Invoice Detail, Invoice Line Detail, Invoices with Credit Notes not Invoiced Again, Journal Activity, Outstanding Invoices, pro forma/quote line and activity views, uncommitted pro forma/quotes, Scheme Credit Report and Tax Invoice.
- **Financial Receipts:** PracticeCtrl receipts plus separately identified imported VeriClaim funder-receipt evidence.
- **Financial Payments (Refunded):** negative receipt/refund evidence plus explicit allocation-reversal/adjustment ledger entries.
- **Financial VAT:** tax-bearing invoices and credit notes; VAT registration remains a governed practice billing-profile setting.
- **External Doctors:** explicit patient referral records linked to subsequent non-void invoice activity. PracticeCtrl never invents or infers a referring provider where no referral was recorded.

### Governed derivation rules

- Liability reports use PracticeCtrl's stored liability states: `scheme_verified`, `patient_verified`, `split_verified`, `credit`, `zero_balance` and `unresolved`.
- Outstanding invoices require a positive balance and exclude void invoices.
- Uncommitted pro forma activity is represented by quotes not converted to an invoice and not rejected/void.
- Journal activity is represented by the structured PracticeCtrl ledger (`invoice`, `credit_note`, `receipt`, `receipt_allocation`, `allocation_reversal`, `writeoff`, `adjustment`, `opening_balance`).
- “Invoices with Credit Notes not Invoiced Again” is intentionally a review list. PracticeCtrl does not infer a replacement invoice from similarity unless a future explicit relation is recorded.
- Imported VeriClaim snapshots remain source-identified and are never silently merged with PracticeCtrl-originated transactions.
