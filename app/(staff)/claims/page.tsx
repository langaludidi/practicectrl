import { ClaimActions } from "@/components/claims/ClaimActions";
import { ClaimSubmissionPanel } from "@/components/claims/ClaimSubmissionPanel";
import { RemittanceVariancePanel } from "@/components/claims/RemittanceVariancePanel";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewRevenue, canManageBilling } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { money, shortDate, shortDateTime } from "@/lib/format";

export default async function ClaimsPage(){
  const staff=await requireStaffContext(); if(!canViewRevenue(staff.role)) return <p className="text-sm text-stone-600">Your role does not have claims access.</p>;
  const supabase=await createClient();
  const [{data:claims},{data:eras},{data:eraLines},{data:invoices},{data:variances}] = await Promise.all([
    supabase.from("claim_record").select("id,invoice_id,patient_id,claim_status,service_from,total_claimed,total_accepted,total_paid,patient_liability,latest_tracking_number,submitted_at,latest_response_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(100),
    supabase.from("remittance_advice").select("id,external_era_ref,payment_date,payment_reference_masked,total_amount,status,received_at,reconciled_at").eq("practice_id",staff.practiceId).order("received_at",{ascending:false}).limit(50),
    supabase.from("remittance_line").select("id,remittance_id,line_no,external_claim_ref,claim_id,claim_line_id,service_date,code,claimed_amount,accepted_amount,paid_amount,patient_liability,reason_code,reason_text").order("created_at",{ascending:false}).limit(200),
    supabase.from("billing_invoice").select("id,invoice_number,status").eq("practice_id",staff.practiceId).order("invoice_date",{ascending:false}).limit(100),
    supabase.from("payer_remittance_variance").select("id,claim_line_id,remittance_line_id,expected_amount,actual_paid_amount,variance_amount,variance_reason,status,notes,reviewed_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(200),
  ]);
  return <div className="space-y-6"><SectionHeader title="Claims & ERA" body="Claim preparation, response exceptions and remittance reconciliation. Matching evidence is deliberately separate from posting money."/>
    {canManageBilling(staff.role)?<ClaimActions invoices={(invoices||[]) as any} claims={(claims||[]) as any} remittanceLines={(eraLines||[]) as any}/>:null}
    <ClaimSubmissionPanel claims={(claims||[]) as any}/>
    {canManageBilling(staff.role)?<RemittanceVariancePanel lines={(eraLines||[]) as any} variances={(variances||[]) as any}/>:null}
    <section className="grid gap-4 xl:grid-cols-2">
      <article className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm"><div className="border-b border-stone-100 px-5 py-4"><h3 className="font-semibold text-[#051a39]">Claims</h3></div><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-stone-50 text-xs text-stone-500"><tr><th className="px-4 py-3">Claim</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Claimed</th><th className="px-4 py-3">Paid</th></tr></thead><tbody>{(claims||[]).map((c:any)=><tr key={c.id} className="border-t border-stone-100"><td className="px-4 py-3"><p className="font-medium">{c.latest_tracking_number||c.id.slice(0,8)}</p><p className="text-xs text-stone-500">Service {shortDate(c.service_from)} · response {shortDateTime(c.latest_response_at)}</p></td><td className="px-4 py-3"><StatusPill value={c.claim_status}/></td><td className="px-4 py-3">{money(c.total_claimed)}</td><td className="px-4 py-3">{money(c.total_paid)}</td></tr>)}</tbody></table></div>{!(claims||[]).length?<p className="p-5 text-sm text-stone-500">No PracticeCtrl claim records yet.</p>:null}</article>
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#051a39]">Remittance advice</h3><div className="mt-4 grid gap-3">{(eras||[]).map((e:any)=><div key={e.id} className="rounded-xl border border-stone-200 p-3"><div className="flex items-center justify-between gap-2"><div><p className="text-sm font-medium">{e.external_era_ref||e.id.slice(0,8)}</p><p className="text-xs text-stone-500">{shortDate(e.payment_date)} · ref {e.payment_reference_masked||"—"} · {shortDateTime(e.received_at)}</p></div><div className="text-right"><StatusPill value={e.status}/><p className="mt-1 text-sm font-medium">{money(e.total_amount)}</p></div></div><p className="mt-2 text-xs text-stone-500">{(eraLines||[]).filter((l:any)=>l.remittance_id===e.id).length} line(s), {(eraLines||[]).filter((l:any)=>l.remittance_id===e.id&&l.claim_id).length} matched</p></div>)}{!(eras||[]).length?<p className="text-sm text-stone-500">No ERA/remittance advice received yet.</p>:null}</div></article>
    </section>
  </div>;
}
