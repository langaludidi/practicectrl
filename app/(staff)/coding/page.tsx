import { CodingStandalone } from "@/components/CodingStandalone";
import { requireStaffContext } from "@/lib/auth/server";
import { canConfirmClinicalCode } from "@/lib/auth/roles";
export default async function CodingPage(){const staff=await requireStaffContext();return <div className="space-y-6"><div><h2 className="text-3xl font-semibold text-[#4a1f3e]">Clinical coding</h2><p className="mt-1 max-w-3xl text-stone-600">South African ICD-10 search and validation. This standalone mode is for controlled coding lookup until the patient-context adapter is connected.</p></div><CodingStandalone practiceId={staff.practiceId} clinicianCanConfirm={canConfirmClinicalCode(staff.role)}/></div>}
