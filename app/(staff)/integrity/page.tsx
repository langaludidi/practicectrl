import { RevenueIntegrityWorkspace } from "@/components/revenue/RevenueIntegrityWorkspace";
import { SectionHeader } from "@/components/SectionHeader";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewRevenue } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { money } from "@/lib/format";

export default async function RevenueIntegrityPage(){
  const staff=await requireStaffContext(); if(!canViewRevenue(staff.role)) return <p className="text-sm text-stone-600">Your role does not have Revenue Integrity access.</p>;
  const supabase=await createClient();
  const [{data:queue},{data:claims}]=await Promise.all([
    supabase.rpc("get_revenue_integrity_queue",{p_practice_id:staff.practiceId,p_limit:150}),
    supabase.from("claim_record").select("id,invoice_id,claim_status,latest_tracking_number").eq("practice_id",staff.practiceId).not("claim_status","in",'(cancelled,reversed)').order("created_at",{ascending:false}).limit(250),
  ]);
  const rows=(queue||[]) as any[]; const blocked=rows.filter(r=>r.status==="blocked"); const review=rows.filter(r=>r.status==="review"); const ready=rows.filter(r=>r.status==="ready");
  const exposure=blocked.reduce((n,r)=>n+Number(r.scheme_portion||0),0); const outstanding=blocked.reduce((n,r)=>n+Number(r.balance_amount||0),0);
  return <div className="space-y-6">
    <SectionHeader title="Revenue Integrity" body="What will stop us getting paid? PracticeCtrl identifies preventable claim failures before submission, routes each exception to corrective action, and rechecks the transaction before it can continue."/>
    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
      <Metric label="Blocked" value={String(blocked.length)} tone="risk"/><Metric label="Needs review" value={String(review.length)}/><Metric label="Ready" value={String(ready.length)} tone="good"/><Metric label="Scheme exposure at risk" value={money(exposure)} tone="risk"/><Metric label="Outstanding on blocked invoices" value={money(outstanding)}/>
    </section>
    <RevenueIntegrityWorkspace rows={rows as any} claims={(claims||[]) as any}/>
  </div>;
}

function Metric({label,value,tone}:{label:string;value:string;tone?:"risk"|"good"}){return <div className="rounded-2xl border border-stone-200 bg-white p-4 shadow-sm"><p className="text-xs uppercase tracking-wide text-stone-500">{label}</p><p className={`mt-2 text-xl font-semibold ${tone==="risk"?"text-rose-700":tone==="good"?"text-emerald-700":"text-[#4a1f3e]"}`}>{value}</p></div>}
