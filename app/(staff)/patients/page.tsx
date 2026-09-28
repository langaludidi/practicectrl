import Link from "next/link";
import { PatientMatchReview } from "@/components/patients/PatientMatchReview";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { canReviewPatientIdentity } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { shortDate } from "@/lib/format";

export default async function PatientsPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const staff = await requireStaffContext();
  const { q } = await searchParams;
  const search = typeof q === "string" ? q.trim().slice(0, 80) : "";
  const supabase = await createClient();
  let patientQuery = supabase.from("crm_patient")
    .select("id,display_name,account_ref,file_ref,date_of_birth,primary_phone,primary_email,status,data_quality_status,source_system,source_last_seen_at")
    .eq("practice_id", staff.practiceId);
  if (search) patientQuery = patientQuery.ilike("display_name", `%${search}%`);
  const [patientResult, candidateResult] = await Promise.all([
    patientQuery.order("display_name").limit(500),
    canReviewPatientIdentity(staff.role)
      ? supabase.from("crm_patient_match_candidate").select("id,patient_a_id,patient_b_id,match_score,match_reasons,status")
        .eq("practice_id", staff.practiceId).order("match_score", { ascending: false }).limit(100)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (patientResult.error || candidateResult.error) throw new Error("The patient directory could not load.");
  const patients = patientResult.data ?? [];
  const candidates = candidateResult.data ?? [];

  return <div className="space-y-6">
    <SectionHeader title="Patients" body="CRM patient context is source-linked and auditable. Matching candidates are reviewed manually; no automatic merging is allowed." />
    <form action="/patients" method="get" role="search" className="flex flex-wrap items-end gap-3 rounded-xl border border-stone-200 bg-white p-4">
      <label className="min-w-[200px] flex-1 text-sm font-medium text-[#051a39]">Find a patient by name
        <input type="search" name="q" maxLength={80} defaultValue={search} placeholder="Enter a patient name" className="mt-1 block w-full rounded-lg border border-[#dce3ea] px-3 py-2.5 text-sm focus:border-[#236cfb]" />
      </label>
      <button className="rounded-lg bg-[#067c80] px-4 py-2.5 text-sm font-semibold text-white">Search</button>
      {search ? <Link href="/patients" className="rounded-lg border border-[#dce3ea] px-4 py-2.5 text-sm font-medium text-[#051a39]">Clear</Link> : null}
    </form>
    <div className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm">
      <div className="overflow-x-auto"><table className="w-full text-left text-sm">
        <thead className="bg-stone-50 text-xs uppercase tracking-wide text-stone-500"><tr><th scope="col" className="px-4 py-3">Patient</th><th scope="col" className="px-4 py-3">Source</th><th scope="col" className="px-4 py-3">Account</th><th scope="col" className="px-4 py-3">DOB</th><th scope="col" className="px-4 py-3">Quality</th></tr></thead>
        <tbody>{patients.map(patient => <tr key={patient.id} className="border-t border-stone-100">
          <td className="px-4 py-3"><Link href={`/patients/${patient.id}`} className="font-medium text-[#067c80] hover:underline">{patient.display_name}</Link><p className="mt-1 text-xs text-stone-500">{patient.primary_phone || patient.primary_email || "No primary contact"}</p></td>
          <td className="px-4 py-3 text-xs text-stone-600">{patient.source_system}</td>
          <td className="px-4 py-3 text-xs text-stone-600">{patient.account_ref || "—"}<br />{patient.file_ref ? `File ${patient.file_ref}` : ""}</td>
          <td className="px-4 py-3 text-xs text-stone-600">{shortDate(patient.date_of_birth)}</td>
          <td className="px-4 py-3"><StatusPill value={patient.data_quality_status} /></td>
        </tr>)}</tbody>
      </table></div>
      {!patients.length ? <p className="p-6 text-sm text-stone-500">{search ? "No patient names matched your search." : "No patients have been promoted into PracticeCtrl yet. A validated VeriClaim import can create source-linked patient records without changing VeriClaim itself."}</p> : null}
      {patients.length === 500 ? <p className="border-t border-stone-100 px-4 py-3 text-xs text-stone-600">Showing the first 500 patients. Narrow your search by name.</p> : null}
    </div>
    {canReviewPatientIdentity(staff.role) ? <PatientMatchReview practiceId={staff.practiceId} userId={staff.userId} candidates={candidates as any} /> : null}
  </div>;
}
