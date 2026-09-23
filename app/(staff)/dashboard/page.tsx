import Link from "next/link";
import { MetricCard } from "@/components/MetricCard";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { money, shortDateTime } from "@/lib/format";

export default async function DashboardPage() {
  const staff=await requireStaffContext(); const supabase=await createClient();
  const [{data:metrics},{data:work},{data:imports}] = await Promise.all([
    supabase.rpc("get_practicectrl_dashboard_metrics",{p_practice_id:staff.practiceId}),
    supabase.from("operations_work_item").select("id,title,category,priority,status,due_at,blocked_reason").eq("practice_id",staff.practiceId).in("status",["open","in_progress","waiting","blocked"]).order("priority",{ascending:false}).order("due_at",{ascending:true}).limit(8),
    supabase.from("vericlaim_import_batch").select("id,report_type,status,created_at,row_count,rejected_row_count").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(5),
  ]);
  const m=(metrics||{}) as any;
  return <div className="space-y-6"><SectionHeader title="Today" body="One operational view across requests, patient work, coding, billing, claims and revenue exceptions." />
    <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <MetricCard label="Open requests" value={String(m.appointment_requests_open ?? 0)} note="PMS confirmation queue"/>
      <MetricCard label="Open work items" value={String(m.operations_open ?? 0)} note="Cross-module accountability"/>
      <MetricCard label="Claim exceptions" value={String(m.claims_exception ?? 0)} note="Rejected / exception / partial"/>
      <MetricCard label="PracticeCtrl invoice balance" value={money(m.invoice_balance ?? 0)} note="Does not replace VeriClaim source snapshots"/>
    </section>
    <section className="grid gap-4 xl:grid-cols-[1.25fr_.75fr]">
      <article className="rounded-2xl border border-stone-200 bg-white p-6 shadow-sm"><div className="flex items-center justify-between"><h3 className="font-semibold text-[#4a1f3e]">Work requiring attention</h3><Link href="/operations" className="text-sm font-medium text-[#e5533d]">Open operations →</Link></div><div className="mt-4 grid gap-3">{(work||[]).map((w:any)=><div key={w.id} className="flex flex-wrap items-start justify-between gap-3 rounded-xl border border-stone-200 p-3"><div><p className="text-sm font-medium">{w.title}</p><p className="mt-1 text-xs text-stone-500">{w.category} · due {shortDateTime(w.due_at)}{w.blocked_reason?` · ${w.blocked_reason}`:""}</p></div><div className="flex gap-2"><StatusPill value={w.priority}/><StatusPill value={w.status}/></div></div>)}{!(work||[]).length?<p className="text-sm text-stone-500">No open work items.</p>:null}</div></article>
      <article className="rounded-2xl border border-stone-200 bg-white p-6 shadow-sm"><div className="flex items-center justify-between"><h3 className="font-semibold text-[#4a1f3e]">Recent VeriClaim imports</h3><Link href="/admin/imports" className="text-sm font-medium text-[#e5533d]">Imports →</Link></div><div className="mt-4 grid gap-3">{(imports||[]).map((x:any)=><div key={x.id} className="rounded-xl border border-stone-200 p-3"><div className="flex items-center justify-between gap-2"><p className="text-sm font-medium">{x.report_type}</p><StatusPill value={x.status}/></div><p className="mt-1 text-xs text-stone-500">{x.row_count} rows · {x.rejected_row_count} rejected · {shortDateTime(x.created_at)}</p></div>)}{!(imports||[]).length?<p className="text-sm text-stone-500">No VeriClaim batch has been promoted yet.</p>:null}</div></article>
    </section>
    <section className="rounded-2xl border border-amber-200 bg-amber-50 p-5 text-sm leading-6 text-amber-900"><strong>System boundary:</strong> VeriClaim source evidence remains immutable and separate from PracticeCtrl-created invoices/receipts. The PMS remains the appointment diary. Code10 remains clinician-confirmed decision support.</section>
  </div>;
}
