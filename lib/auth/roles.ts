export const STAFF_ROLES = [
  "practitioner", "reception", "billing", "finance", "coder", "practice_manager", "clinical_admin", "auditor", "system_admin"
] as const;
export type StaffRole = typeof STAFF_ROLES[number];

export function canConfirmClinicalCode(role: StaffRole) { return role === "practitioner"; }
export function canViewRevenue(role: StaffRole) { return ["billing","finance","practice_manager","system_admin","auditor"].includes(role); }
export function canManageBilling(role: StaffRole) { return ["billing","finance","practice_manager","system_admin"].includes(role); }
export function canViewEconomics(role: StaffRole) { return ["billing","finance","coder","practice_manager","system_admin","auditor","practitioner"].includes(role); }
export function canManageRecovery(role: StaffRole) { return ["billing","finance","practice_manager","system_admin"].includes(role); }
export function canViewRecovery(role: StaffRole) { return ["billing","finance","coder","practice_manager","system_admin","auditor"].includes(role); }
export function canManageRequests(role: StaffRole) { return ["reception","practice_manager","clinical_admin","system_admin"].includes(role); }
export function canManageOperations(role: StaffRole) { return role !== "auditor"; }
export function canReviewPatientIdentity(role: StaffRole) { return ["practice_manager","clinical_admin","system_admin"].includes(role); }

export function canViewClinicalRecords(role: StaffRole) { return ["practitioner","clinical_admin","practice_manager","system_admin","auditor"].includes(role); }
export function canManageClinicalRecords(role: StaffRole) { return ["practitioner","clinical_admin"].includes(role); }
export function canViewPathology(role: StaffRole) { return canViewClinicalRecords(role); }
export function canManagePathology(role: StaffRole) { return ["practitioner","clinical_admin"].includes(role); }
export function canSubmitPathology(role: StaffRole) { return role === "practitioner"; }

export function canViewMedicines(role: StaffRole) { return canViewClinicalRecords(role); }
export function canManageMedicines(role: StaffRole) { return ["practitioner","clinical_admin"].includes(role); }
export function canPrescribeMedicines(role: StaffRole) { return role === "practitioner"; }

export function canScheduleAppointments(role: StaffRole) { return ["reception","practice_manager","clinical_admin","system_admin"].includes(role); }
export function canConfigureAppointments(role: StaffRole) { return ["practice_manager","system_admin"].includes(role); }
