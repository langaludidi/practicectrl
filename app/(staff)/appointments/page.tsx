import Link from "next/link";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { shortDate, shortDateTime } from "@/lib/format";

export default async function AppointmentsPage() {
  const staff = await requireStaffContext();
  const supabase = await createClient();
  const [{ data: requests, error: requestsError }, { data: legacy, error: legacyError }] = await Promise.all([
    supabase.from("appointment_request")
      .select("id,requester_name,requested_service,preferred_date,preferred_time,status,pms_reference,updated_at")
      .eq("practice_id", staff.practiceId).order("created_at", { ascending: false }).limit(100),
    supabase.from("practice_appointment")
      .select("id,appointment_number,starts_at,status")
      .eq("practice_id", staff.practiceId).order("starts_at", { ascending: false }).limit(50),
  ]);
  const rows = requests ?? [];
  const outstanding = rows.filter(r => !["Confirmed in PMS", "Booked in PracticeCtrl", "Closed", "Duplicate"].includes(r.status));
  const confirmed = rows.filter(r => r.status === "Confirmed in PMS");
  return <div className="space-y-6">
    <SectionHeader title="Appointment handoff" body="The PMS is the authoritative appointment diary. PracticeCtrl tracks requests, follow-up and the PMS confirmation reference; appointment times and changes must be made in the PMS." />
    <section aria-label="Appointment handoff summary" className="grid gap-4 sm:grid-cols-2">
      <div className="rounded-xl border border-[#dce3ea] bg-white p-5"><p className="text-sm text-stone-600">Requests needing action</p><p className="mt-2 text-3xl font-semibold text-[#051a39]">{requestsError ? "—" : outstanding.length}</p><p className="text-xs text-stone-600">Among the latest 100 requests</p></div>
      <div className="rounded-xl border border-[#dce3ea] bg-white p-5"><p className="text-sm text-stone-600">Confirmed in PMS</p><p className="mt-2 text-3xl font-semibold text-[#051a39]">{requestsError ? "—" : confirmed.length}</p><p className="text-xs text-stone-600">Among the latest 100 requests</p></div>
    </section>
    <section className="rounded-xl border border-[#bfdbfe] bg-[#eff6ff] p-5 text-sm leading-6 text-[#1e3a5f]">
      <strong className="text-[#051a39]">Booking handoff:</strong> review the request → book or change the appointment in the PMS → record its reference on the request. PracticeCtrl does not create or reschedule diary entries.
      <Link href="/requests" className="ml-2 font-semibold text-[#067c80] underline">Open requests</Link>
    </section>
    <section className="overflow-hidden rounded-xl border border-[#dce3ea] bg-white">
      <div className="border-b border-[#e5eaf0] px-5 py-4"><h2 className="font-semibold text-[#051a39]">Recent request handoffs</h2></div>
      {requestsError ? <p role="alert" className="p-5 text-sm text-red-700">Requests could not be loaded. Refresh this page or contact your administrator.</p> :
        rows.length ? <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-stone-50 text-xs text-stone-600"><tr><th scope="col" className="px-4 py-3">Requester</th><th scope="col" className="px-4 py-3">Preferred time</th><th scope="col" className="px-4 py-3">Status</th><th scope="col" className="px-4 py-3">PMS reference</th><th scope="col" className="px-4 py-3">Updated</th></tr></thead><tbody>{rows.map(r => <tr key={r.id} className="border-t border-stone-100"><td className="px-4 py-3"><span className="font-medium">{r.requester_name}</span><span className="block text-xs text-stone-600">{r.requested_service || "Service unspecified"}</span></td><td className="px-4 py-3">{shortDate(r.preferred_date)} {r.preferred_time || ""}</td><td className="px-4 py-3"><StatusPill value={r.status} /></td><td className="px-4 py-3">{r.pms_reference || "—"}</td><td className="px-4 py-3">{shortDateTime(r.updated_at)}</td></tr>)}</tbody></table></div> : <p className="p-5 text-sm text-stone-600">No requests yet. New requests will appear here for PMS handoff.</p>}
    </section>
    {legacyError ? <p role="alert" className="text-sm text-red-700">Historical PracticeCtrl appointments could not be loaded.</p> : legacy?.length ? <details className="rounded-xl border border-[#dce3ea] bg-white p-5"><summary className="cursor-pointer font-semibold text-[#051a39]">Historical PracticeCtrl appointments ({legacy.length})</summary><p className="mt-2 text-sm text-stone-600">These are existing local records for review. Verify all current appointment details in the PMS.</p><ul className="mt-3 divide-y divide-stone-100 text-sm">{legacy.map(a => <li key={a.id} className="flex flex-wrap justify-between gap-2 py-2"><span>{a.appointment_number} · {shortDateTime(a.starts_at)}</span><StatusPill value={a.status} /></li>)}</ul></details> : null}
  </div>;
}
