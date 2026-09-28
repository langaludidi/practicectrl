export const STAFF_ROLES = [
  "practitioner", "reception", "billing", "finance", "coder", "practice_manager", "clinical_admin", "auditor", "system_admin"
] as const;
export type StaffRole = typeof STAFF_ROLES[number];

const FINANCIAL_READ_ROLES = ["billing", "finance", "practice_manager", "system_admin", "auditor"] as const satisfies readonly StaffRole[];
const BILLING_MANAGEMENT_ROLES = ["billing", "practice_manager", "system_admin"] as const satisfies readonly StaffRole[];
const REVENUE_CONTROL_MANAGEMENT_ROLES = ["billing", "finance", "practice_manager", "system_admin"] as const satisfies readonly StaffRole[];
const VERICLAIM_IMPORT_MANAGEMENT_ROLES = ["billing", "practice_manager", "system_admin"] as const satisfies readonly StaffRole[];

function hasRole(role: StaffRole, roles: readonly StaffRole[]) {
  return roles.includes(role);
}

export function canConfirmClinicalCode(role: StaffRole) { return role === "practitioner"; }
export function canViewRevenue(role: StaffRole) { return hasRole(role, FINANCIAL_READ_ROLES); }
export function canManageBilling(role: StaffRole) { return hasRole(role, BILLING_MANAGEMENT_ROLES); }
export function canManageRevenueControl(role: StaffRole) { return hasRole(role, REVENUE_CONTROL_MANAGEMENT_ROLES); }
export function canManageVeriClaimImports(role: StaffRole) { return hasRole(role, VERICLAIM_IMPORT_MANAGEMENT_ROLES); }
export function canViewEconomics(role: StaffRole) { return ["billing","finance","coder","practice_manager","system_admin","auditor","practitioner"].includes(role); }
export function canManageRecovery(role: StaffRole) { return ["billing","finance","practice_manager","system_admin"].includes(role); }
export function canViewRecovery(role: StaffRole) { return ["billing","finance","coder","practice_manager","system_admin","auditor"].includes(role); }
export function canManageRequests(role: StaffRole) { return ["reception","practice_manager","clinical_admin","system_admin"].includes(role); }
export function canManageOperations(role: StaffRole) { return role !== "auditor"; }
export function canReviewPatientIdentity(role: StaffRole) { return ["practice_manager","clinical_admin","system_admin"].includes(role); }

export function canViewClinicalRecords(role: StaffRole) { return role === "practitioner"; }
export function canManageClinicalRecords(role: StaffRole) { return role === "practitioner"; }
export function canViewPathology(role: StaffRole) { return canViewClinicalRecords(role); }
export function canManagePathology(role: StaffRole) { return role === "practitioner"; }
export function canSubmitPathology(role: StaffRole) { return role === "practitioner"; }

export function canViewMedicines(role: StaffRole) { return canViewClinicalRecords(role); }
export function canManageMedicines(role: StaffRole) { return role === "practitioner"; }
export function canPrescribeMedicines(role: StaffRole) { return role === "practitioner"; }
