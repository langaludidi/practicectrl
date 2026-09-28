import Link from "next/link";
import { RequestStatusActions } from "@/components/requests/RequestStatusActions";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { canManageRequests } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { shortDate, shortDateTime } from "@/lib/format";

export default async function RequestsPage() {
  const staff = await requireStaffContext();
  const supabase = await createClient();
  const { data, error } = await supabase.from("appointment_request")
    .select("id,requester_name,requester_phone,requester_email,requested_service,preferred_date,preferred_time,status,source,pms_reference,updated_at")
    .eq("practice_id", staff.practiceId).order("created_at", { ascending: false }).limit(100);

  return <div className="space-y-6">
    <SectionHeader title="Appointment requests" body="Contact the patient, book in the PMS, then enter the PMS appointment reference here to confirm the handoff. The PMS controls appointment times and changes." />
    <p className="rounded-xl border border-[#bfdbfe] bg-[#eff6ff] p-4 text-sm text-[#1e3a5f]">
      <strong>The PMS is the appointment diary.</strong> A preferred date on a request is not a booking. <Link href="/appointments" className="font-semibold text-[#067c80] underline">View the handoff</Link>.
    </p>
    <div className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm">
      {error ? <p role="alert" className="p-6 text-sm text-red-700">Appointment requests could not be loaded. Refresh this page or contact your administrator.</p> : <>
        <div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-stone-50 text-xs text-stone-600"><tr><th scope="col" className="px-4 py-3">Requester</th><th scope="col" className="px-4 py-3">Preference</th><th scope="col" className="px-4 py-3">Source</th><th scope="col" className="px-4 py-3">Status and action</th><th scope="col" className="px-4 py-3">Updated</th></tr></thead>
          <tbody>{(data || []).map(r => <tr key={r.id} className="border-t border-stone-100 align-top">
            <td className="px-4 py-3"><p className="font-medium">{r.requester_name}</p><p className="mt-1 text-xs text-stone-600">{r.requester_phone || r.requester_email || "No contact"}{r.requested_service ? ` · ${r.requested_service}` : ""}</p></td>
            <td className="px-4 py-3 text-xs text-stone-600">{shortDate(r.preferred_date)} {r.preferred_time || ""}</td>
            <td className="px-4 py-3 text-xs text-stone-600">{r.source}</td>
            <td className="px-4 py-3"><div className="mb-1"><StatusPill value={r.status} /></div>{canManageRequests(staff.role) ? <RequestStatusActions id={r.id} status={r.status} /> : null}{r.pms_reference ? <p className="mt-1 text-xs text-stone-600">PMS reference: {r.pms_reference}</p> : null}</td>
            <td className="px-4 py-3 text-xs text-stone-600">{shortDateTime(r.updated_at)}</td>
          </tr>)}</tbody></table></div>
        {!(data || []).length ? <p className="p-6 text-sm text-stone-600">No appointment requests have been received yet.</p> : null}
      </>}
    </div>
  </div>;
}
