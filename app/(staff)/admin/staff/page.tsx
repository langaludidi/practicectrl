import { redirect } from "next/navigation";
import { StaffAccessPanel } from "@/components/admin/StaffAccessPanel";
import { SectionHeader } from "@/components/SectionHeader";
import { requireStaffContext } from "@/lib/auth/server";
export default async function StaffAccessPage(){const staff=await requireStaffContext();if(!["system_admin","practice_manager","auditor"].includes(staff.role))redirect("/dashboard");return <div className="space-y-6"><SectionHeader title="Staff & Access" body="Governed onboarding, role assignment and invitation history. MFA remains mandatory for staff application access."/><StaffAccessPanel role={staff.role} practiceId={staff.practiceId}/></div>}
