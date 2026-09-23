import type { StaffRole } from "@/lib/auth/roles";

export type ReportSurface =
  | "Live workspace"
  | "Filtered view"
  | "Drill-down"
  | "Audit trail"
  | "Governance view";

export type ReportDefinition = {
  id: string;
  category: string;
  legacyName: string;
  practiceCtrlName: string;
  description: string;
  href: string;
  surface: ReportSurface;
  roles: readonly StaffRole[];
  keywords?: readonly string[];
};

const ALL: readonly StaffRole[] = ["practitioner","reception","billing","finance","coder","practice_manager","clinical_admin","auditor","system_admin"];
const FIN: readonly StaffRole[] = ["billing","finance","practice_manager","auditor","system_admin"];
const FIN_EDIT: readonly StaffRole[] = ["billing","finance","practice_manager","system_admin"];
const CLINICAL: readonly StaffRole[] = ["practitioner","coder","clinical_admin","practice_manager","auditor","system_admin"];
const MANAGER: readonly StaffRole[] = ["practice_manager","auditor","system_admin"];
const COMMS: readonly StaffRole[] = ["reception","billing","finance","practice_manager","auditor","system_admin"];

export const REPORT_DEFINITIONS: readonly ReportDefinition[] = [
  // Batch Mailing
  { id:"batch-mailing-print-detail",category:"Batch Mailing",legacyName:"Batch Mailing Print Detail",practiceCtrlName:"Outbound communication activity",description:"Review outbound batch communication records and message detail in the Communications workspace.",href:"/communications?view=batch-detail",surface:"Filtered view",roles:COMMS },
  { id:"batch-mailing-status",category:"Batch Mailing",legacyName:"Batch Mailing Status",practiceCtrlName:"Communication delivery status",description:"Track prepared, queued, sent, failed and governed communication states.",href:"/communications?view=delivery-status",surface:"Live workspace",roles:COMMS },
  { id:"legal-notice-detail",category:"Batch Mailing",legacyName:"Legal Notice Detail",practiceCtrlName:"Recovery communication evidence",description:"Review collection/legal-notice communication evidence without exposing clinical detail.",href:"/recovery?view=communication-evidence",surface:"Drill-down",roles:FIN },

  // Billing Templates
  { id:"submitted-cancelled-treatment-date",category:"Billing Templates",legacyName:"Submitted But Cancelled Billing Templates — By Treatment Date",practiceCtrlName:"Cancelled billing drafts by service date",description:"Filter cancelled/submitted billing drafts by date of service.",href:"/billing?view=cancelled-drafts&group=date",surface:"Filtered view",roles:FIN },
  { id:"submitted-cancelled-provider",category:"Billing Templates",legacyName:"Submitted But Cancelled Billing Templates — By Treatment Date Per Provider",practiceCtrlName:"Cancelled billing drafts by practitioner",description:"Review cancelled/submitted billing drafts grouped by practitioner and date.",href:"/billing?view=cancelled-drafts&group=practitioner",surface:"Filtered view",roles:FIN },
  { id:"submitted-cancelled-service-centre",category:"Billing Templates",legacyName:"Submitted But Cancelled Billing Templates — By Treatment Date Per Provider Per Service Centre",practiceCtrlName:"Cancelled billing drafts by practitioner and location",description:"Review cancelled/submitted drafts by service date, practitioner and practice location.",href:"/billing?view=cancelled-drafts&group=location",surface:"Filtered view",roles:FIN },
  { id:"template-no-invoice-treatment-date",category:"Billing Templates",legacyName:"Billing Template But No Invoice — By Treatment Date",practiceCtrlName:"Uncommitted billing drafts by service date",description:"Find completed billing templates/drafts that have not produced an invoice.",href:"/billing?view=uncommitted-drafts&group=date",surface:"Filtered view",roles:FIN },
  { id:"template-no-invoice-provider",category:"Billing Templates",legacyName:"Billing Template But No Invoice — By Treatment Date Per Provider",practiceCtrlName:"Uncommitted billing drafts by practitioner",description:"Find uncommitted billing drafts by practitioner and service date.",href:"/billing?view=uncommitted-drafts&group=practitioner",surface:"Filtered view",roles:FIN },
  { id:"template-no-invoice-service-centre",category:"Billing Templates",legacyName:"Billing Template But No Invoice — By Treatment Date Per Provider Per Service Centre",practiceCtrlName:"Uncommitted billing drafts by practitioner and location",description:"Find uncommitted drafts grouped by practitioner, location and service date.",href:"/billing?view=uncommitted-drafts&group=location",surface:"Filtered view",roles:FIN },

  // Coding Activity
  { id:"coding-consultation",category:"Coding Activity",legacyName:"Consultation",practiceCtrlName:"Encounter and consultation activity",description:"Review completed encounters and consultation-linked coding activity.",href:"/clinical?view=consultations",surface:"Filtered view",roles:CLINICAL },
  { id:"coding-icd10",category:"Coding Activity",legacyName:"Diagnosis Codes (ICD10)",practiceCtrlName:"Code10 diagnosis activity",description:"Review ICD-10 usage, confirmation and coding provenance through Code10.",href:"/coding?view=diagnoses",surface:"Live workspace",roles:CLINICAL },
  { id:"coding-nappi",category:"Coding Activity",legacyName:"Materials (Nappi)",practiceCtrlName:"Medicines/material reference activity",description:"Review medicines/material references and NAPPI-linked activity where licensed source data is available.",href:"/medicines?view=nappi",surface:"Live workspace",roles:["practitioner","clinical_admin","practice_manager","auditor","system_admin"] },
  { id:"coding-modifier",category:"Coding Activity",legacyName:"Modifier",practiceCtrlName:"Modifier activity",description:"Review modifier use, coding support and claim-line application.",href:"/coding?view=modifiers",surface:"Filtered view",roles:CLINICAL },
  { id:"coding-procedure",category:"Coding Activity",legacyName:"Procedure",practiceCtrlName:"Procedure activity",description:"Review procedure utilisation with coding, claim-line and RVU/IRU drill-downs.",href:"/economics?dimension=procedure",surface:"Drill-down",roles:["practitioner","coder","billing","finance","practice_manager","auditor","system_admin"] },

  // Diary Activity
  { id:"diary-bookings",category:"Diary Activity",legacyName:"Diary Bookings",practiceCtrlName:"Appointment activity",description:"Review bookings, attendance states, practitioner schedules and appointment activity.",href:"/appointments?view=activity",surface:"Live workspace",roles:["practitioner","reception","practice_manager","clinical_admin","auditor","system_admin"] },

  // External Doctors
  { id:"referring-provider-invoices",category:"External Doctors",legacyName:"Invoices From Referring Provider",practiceCtrlName:"Referring-provider activity",description:"Trace referring-provider relationships into encounters, authorisations and related invoice activity.",href:"/authorisations?view=referring-providers",surface:"Drill-down",roles:["practitioner","billing","finance","practice_manager","clinical_admin","auditor","system_admin"] },

  // Financial Age Analysis
  { id:"age-combined",category:"Financial Age Analysis",legacyName:"Age Analysis Combined Scheme & Patient",practiceCtrlName:"Combined debtor ageing",description:"Combined scheme and patient outstanding balances with liability separation.",href:"/revenue?view=ageing&liability=combined",surface:"Live workspace",roles:FIN },
  { id:"age-combined-credit",category:"Financial Age Analysis",legacyName:"Age Analysis Combined Scheme & Patient (Only Credit Totals)",practiceCtrlName:"Credit-balance ageing",description:"Show credit balances only across scheme and patient accounts.",href:"/revenue?view=ageing&balance=credit",surface:"Filtered view",roles:FIN },
  { id:"age-combined-debit",category:"Financial Age Analysis",legacyName:"Age Analysis Combined Scheme & Patient (Only Debit Totals)",practiceCtrlName:"Debit-balance ageing",description:"Show debit/outstanding balances only across scheme and patient accounts.",href:"/revenue?view=ageing&balance=debit",surface:"Filtered view",roles:FIN },
  { id:"age-by-account",category:"Financial Age Analysis",legacyName:"Age Analysis Combined Scheme & Patient (Sorted by AccNo)",practiceCtrlName:"Ageing by account",description:"Ageing view sorted/grouped by account reference.",href:"/revenue?view=ageing&sort=account",surface:"Filtered view",roles:FIN },
  { id:"age-by-file",category:"Financial Age Analysis",legacyName:"Age Analysis Combined Scheme & Patient (Sorted by FileNo)",practiceCtrlName:"Ageing by patient/file reference",description:"Ageing view sorted/grouped by patient or legacy file reference where imported.",href:"/revenue?view=ageing&sort=file",surface:"Filtered view",roles:FIN },
  { id:"age-patient-liable",category:"Financial Age Analysis",legacyName:"Age Analysis for Patient Liable",practiceCtrlName:"Patient-liability ageing",description:"Outstanding verified patient-responsibility balances with recovery state.",href:"/revenue?view=ageing&liability=patient",surface:"Drill-down",roles:FIN },
  { id:"age-scheme-liable",category:"Financial Age Analysis",legacyName:"Age Analysis for Scheme Liable",practiceCtrlName:"Scheme-liability ageing",description:"Outstanding scheme-responsibility balances linked to claims and remittances.",href:"/revenue?view=ageing&liability=scheme",surface:"Drill-down",roles:FIN },
  { id:"age-summary",category:"Financial Age Analysis",legacyName:"Age Analysis summary",practiceCtrlName:"Ageing summary",description:"Summary ageing by liability type, age bucket and outstanding value.",href:"/revenue?view=ageing&summary=1",surface:"Live workspace",roles:FIN },

  // Financial Generic
  { id:"accounts-credit",category:"Financial Generic",legacyName:"Accounts in Credit",practiceCtrlName:"Credit balances",description:"Identify patient or scheme accounts with net credit balances.",href:"/revenue?view=credit-balances",surface:"Filtered view",roles:FIN },
  { id:"credit-note-report",category:"Financial Generic",legacyName:"Credit Note Report",practiceCtrlName:"Credit-note activity",description:"Review credit notes and their relationship to invoices, balances and adjustments.",href:"/billing?view=credit-notes",surface:"Filtered view",roles:FIN },
  { id:"daily-activity",category:"Financial Generic",legacyName:"Daily Activity Report",practiceCtrlName:"Daily practice activity",description:"Daily operational and financial activity using Command Centre and source drill-downs.",href:"/analytics?window=7",surface:"Live workspace",roles:FIN },
  { id:"daily-report-old",category:"Financial Generic",legacyName:"Daily Report (Old)",practiceCtrlName:"Daily practice activity",description:"Legacy daily-report information is consolidated into the current Command Centre rather than reproduced as a second report.",href:"/analytics?window=7",surface:"Live workspace",roles:FIN },
  { id:"invoice-activity",category:"Financial Generic",legacyName:"Invoice Activity",practiceCtrlName:"Invoice activity",description:"Invoice creation, finalisation, status and amount activity.",href:"/billing?view=invoice-activity",surface:"Live workspace",roles:FIN },
  { id:"invoice-activity-schemes",category:"Financial Generic",legacyName:"Invoice Activity for Schemes",practiceCtrlName:"Invoice activity by payer",description:"Invoice and expected-revenue activity sliced by medical scheme and plan.",href:"/economics?dimension=scheme",surface:"Drill-down",roles:FIN },
  { id:"invoice-detail",category:"Financial Generic",legacyName:"Invoice Detail",practiceCtrlName:"Invoice detail",description:"Open invoice headers, payer resolution, patient liability and line-level detail.",href:"/billing?view=invoices",surface:"Live workspace",roles:FIN },
  { id:"invoice-income-activity",category:"Financial Generic",legacyName:"Invoice Income Activity",practiceCtrlName:"Expected vs realised revenue",description:"Connect invoiced activity to adjudication, payments, patient collections and realisation.",href:"/economics",surface:"Live workspace",roles:FIN },
  { id:"invoice-line-detail",category:"Financial Generic",legacyName:"Invoice Line Detail",practiceCtrlName:"Claim-line economics",description:"Line-level procedure, modifier, diagnosis, tariff, expected and realised reimbursement detail.",href:"/economics?dimension=procedure",surface:"Drill-down",roles:FIN },
  { id:"credit-not-reinvoiced",category:"Financial Generic",legacyName:"Invoices with Credit Notes not Invoiced Again",practiceCtrlName:"Credit-note follow-up exceptions",description:"Surface credited invoices without a corresponding corrected/replacement billing outcome.",href:"/billing?view=credit-note-followup",surface:"Filtered view",roles:FIN_EDIT },
  { id:"journal-activity",category:"Financial Generic",legacyName:"Journal Activity",practiceCtrlName:"Financial audit activity",description:"Trace billing, payment, adjustment and recovery events through immutable audit history.",href:"/audit?entity=billing",surface:"Audit trail",roles:FIN },
  { id:"outstanding-invoices",category:"Financial Generic",legacyName:"Outstanding Invoices",practiceCtrlName:"Outstanding invoice worklist",description:"Review invoice balances with payer/patient liability, ageing and recovery state.",href:"/revenue?view=outstanding-invoices",surface:"Live workspace",roles:FIN },
  { id:"proforma-line",category:"Financial Generic",legacyName:"Pro forma (only) Line Detail",practiceCtrlName:"Draft invoice line detail",description:"Review unfinalised/pro forma billing lines before invoice finalisation.",href:"/billing?view=proforma-lines",surface:"Filtered view",roles:FIN },
  { id:"proforma-activity",category:"Financial Generic",legacyName:"Pro forma Activity",practiceCtrlName:"Draft billing activity",description:"Review pro forma/draft invoice activity and progression to final invoice.",href:"/billing?view=proforma",surface:"Filtered view",roles:FIN },
  { id:"proforma-uncommitted",category:"Financial Generic",legacyName:"Pro forma’s Not Committed",practiceCtrlName:"Uncommitted billing drafts",description:"Find draft/pro forma billing that has not been finalised or deliberately cancelled.",href:"/billing?view=uncommitted-proforma",surface:"Filtered view",roles:FIN_EDIT },
  { id:"scheme-credit",category:"Financial Generic",legacyName:"Scheme Credit Report",practiceCtrlName:"Scheme credit balances",description:"Review payer/scheme credit balances and reconciliation exceptions.",href:"/revenue?view=scheme-credit",surface:"Filtered view",roles:FIN },
  { id:"tax-invoice",category:"Financial Generic",legacyName:"Tax Invoice",practiceCtrlName:"Finalised tax invoices",description:"Access finalised invoice records and printable tax-invoice detail where configured.",href:"/billing?view=tax-invoices",surface:"Live workspace",roles:FIN },

  // Other visible legacy report families
  { id:"assistant-information",category:"Assistant Information",legacyName:"Assistant Information",practiceCtrlName:"AI & automation governance",description:"Review enabled AI/voice capabilities, provider governance and policy state instead of opaque assistant reports.",href:"/admin/assist",surface:"Governance view",roles:["system_admin"] },
  { id:"financial-information",category:"Financial Information",legacyName:"Financial Information",practiceCtrlName:"Practice Economics",description:"Financial information is consolidated into Practice Economics with payer, plan, procedure and practitioner drill-downs.",href:"/economics",surface:"Live workspace",roles:FIN },
  { id:"financial-refunds",category:"Financial Payments (Refunded)",legacyName:"Financial Payments (Refunded)",practiceCtrlName:"Refund and reversal activity",description:"Review payment reversals, refunds and resulting balances through revenue and audit views.",href:"/revenue?view=refunds",surface:"Filtered view",roles:FIN },
  { id:"financial-receipts",category:"Financial Receipts (Received)",legacyName:"Financial Receipts (Received)",practiceCtrlName:"Receipt and remittance activity",description:"Review scheme remittances, patient receipts and payment allocations.",href:"/claims?view=receipts",surface:"Drill-down",roles:FIN },
  { id:"financial-vat",category:"Financial VAT",legacyName:"Financial VAT",practiceCtrlName:"VAT/tax invoice activity",description:"Review tax-bearing invoice records and VAT-relevant billing fields where the practice configuration requires them.",href:"/billing?view=vat",surface:"Filtered view",roles:FIN },
  { id:"path-labs",category:"Path Labs",legacyName:"Path Labs",practiceCtrlName:"Pathology Orders & Results",description:"Pathology order, result, report-document, acknowledgement and follow-up activity.",href:"/pathology",surface:"Live workspace",roles:["practitioner","clinical_admin","practice_manager","auditor","system_admin"] },
  { id:"patients-report-family",category:"Patients",legacyName:"Patients",practiceCtrlName:"Patient registry and intake",description:"Patient identity, scheme/option, contact, intake and status information through the patient workspace.",href:"/patients",surface:"Live workspace",roles:ALL },
  { id:"practice-management",category:"Practice Management",legacyName:"Practice Management",practiceCtrlName:"Practice administration",description:"Staff, access, modules, integrations, source governance and audit are distributed across governed administration workspaces.",href:"/admin/staff",surface:"Governance view",roles:MANAGER },
] as const;

export const REPORT_CATEGORIES = [...new Set(REPORT_DEFINITIONS.map(report => report.category))];

export function reportsForRole(role: StaffRole) {
  return REPORT_DEFINITIONS.filter(report => report.roles.includes(role));
}
