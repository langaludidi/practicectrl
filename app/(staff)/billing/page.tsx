import { BillingActions } from "@/components/billing/BillingActions";
import { AllocationPanel } from "@/components/billing/AllocationPanel";
import { InvoiceLineControls } from "@/components/billing/InvoiceLineControls";
import { PayerResolutionPanel } from "@/components/billing/PayerResolutionPanel";
import { ClaimPreflightPanel } from "@/components/billing/ClaimPreflightPanel";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewRevenue, canManageBilling } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { money, shortDate } from "@/lib/format";

export default async function BillingPage(){
  const staff=await requireStaffContext(); if(!canViewRevenue(staff.role)) return <p className="text-sm text-stone-600">Your role does not have billing access.</p>;
  const supabase=await createClient();
  const [{data:invoices},{data:receipts},{data:allocs},{data:patients},{data:lines},{data:practitioners},{data:validations}] = await Promise.all([
    supabase.from("billing_invoice").select("id,invoice_number,invoice_date,status,total_amount,received_amount,balance_amount,patient_id,source_system,medical_scheme_id,medical_scheme_option_id").eq("practice_id",staff.practiceId).order("invoice_date",{ascending:false}).limit(100),
    supabase.from("billing_payment_receipt").select("id,receipt_number,receipt_date,amount,payer_type,patient_id,source_system").eq("practice_id",staff.practiceId).order("receipt_date",{ascending:false}).limit(100),
    supabase.from("billing_payment_allocation").select("id,receipt_id,invoice_id,amount,allocation_status,allocated_at").order("allocated_at",{ascending:false}).limit(100),
    supabase.from("crm_patient").select("id,display_name").eq("practice_id",staff.practiceId).eq("status","active").order("display_name").limit(500),
    supabase.from("billing_invoice_line").select("id,invoice_id,line_no,description_snapshot,line_amount,code_system,code,claim_eligible,reference_amount,expected_contractual_amount,expected_scheme_amount,expected_patient_liability,payer_rule_resolution_id,metadata").order("line_no"),
    supabase.from("practitioner_profile").select("id,display_name").eq("practice_id",staff.practiceId).eq("active",true).order("display_name"),
    supabase.from("billing_validation_event").select("id,invoice_id,invoice_line_id,rule_code,severity,message,status,created_at").eq("source","payer_claim_preflight").order("created_at",{ascending:false}).limit(200),
  ]);
  return <div className="space-y-6"><SectionHeader title="Billing" body="PracticeCtrl-created invoices and receipts are controlled transactions. Imported VeriClaim financial evidence remains in separate immutable snapshot tables."/>
    {canManageBilling(staff.role)?<BillingActions practiceId={staff.practiceId} patients={(patients||[]) as any} invoices={(invoices||[]) as any}/>:null}
    {canManageBilling(staff.role)?<AllocationPanel receipts={(receipts||[]) as any} invoices={(invoices||[]).filter((x:any)=>Number(x.balance_amount)>0) as any}/>:null}
    {canManageBilling(staff.role)?<InvoiceLineControls invoices={(invoices||[]) as any} lines={(lines||[]) as any}/>:null}
    {canManageBilling(staff.role)?<ClaimPreflightPanel invoices={(invoices||[]) as any} validations={(validations||[]) as any}/>:null}
    {canManageBilling(staff.role)?<PayerResolutionPanel invoices={(invoices||[]) as any} lines={(lines||[]) as any} practitioners={(practitioners||[]) as any}/>:null}
    <section className="grid gap-4 xl:grid-cols-2">
      <article className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm"><div className="border-b border-stone-100 px-5 py-4"><h3 className="font-semibold text-[#051a39]">Invoices</h3></div><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-stone-50 text-xs text-stone-500"><tr><th className="px-4 py-3">Invoice</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Total</th><th className="px-4 py-3">Balance</th></tr></thead><tbody>{(invoices||[]).map((i:any)=><tr key={i.id} className="border-t border-stone-100"><td className="px-4 py-3"><p className="font-medium">{i.invoice_number}</p><p className="text-xs text-stone-500">{shortDate(i.invoice_date)} · {i.source_system}</p></td><td className="px-4 py-3"><StatusPill value={i.status}/></td><td className="px-4 py-3">{money(i.total_amount)}</td><td className="px-4 py-3">{money(i.balance_amount)}</td></tr>)}</tbody></table></div>{!(invoices||[]).length?<p className="p-5 text-sm text-stone-500">No PracticeCtrl invoices yet.</p>:null}</article>
      <article className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm"><div className="border-b border-stone-100 px-5 py-4"><h3 className="font-semibold text-[#051a39]">Receipts & allocations</h3></div><div className="p-5"><div className="grid gap-3">{(receipts||[]).slice(0,20).map((r:any)=><div key={r.id} className="rounded-xl border border-stone-200 p-3"><div className="flex items-center justify-between"><div><p className="text-sm font-medium">{r.receipt_number}</p><p className="text-xs text-stone-500">{shortDate(r.receipt_date)} · {r.payer_type} · {r.source_system}</p></div><span className="font-medium">{money(r.amount)}</span></div><p className="mt-2 text-xs text-stone-500">{(allocs||[]).filter((a:any)=>a.receipt_id===r.id&&a.allocation_status==="posted").length} posted allocation(s)</p></div>)}{!(receipts||[]).length?<p className="text-sm text-stone-500">No PracticeCtrl receipts yet.</p>:null}</div></div></article>
    </section>
  </div>;
}
