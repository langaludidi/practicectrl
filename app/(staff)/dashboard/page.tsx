import Link from "next/link";
import { MetricCard } from "@/components/MetricCard";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { money, shortDateTime } from "@/lib/format";

export default async function DashboardPage() {
  const staff = await requireStaffContext();
  const supabase = await createClient();
  const [{ data: metrics }, { data: work }, { data: imports }] = await Promise.all([
    supabase.rpc("get_practicectrl_dashboard_metrics", { p_practice_id: staff.practiceId }),
    supabase.from("operations_work_item").select("id,title,category,priority,status,due_at,blocked_reason").eq("practice_id", staff.practiceId).in("status", ["open","in_progress","waiting","blocked"]).order("priority", { ascending: false }).order("due_at", { ascending: true }).limit(8),
    supabase.from("vericlaim_import_batch").select("id,report_type,status,created_at,row_count,rejected_row_count").eq("practice_id", staff.practiceId).order("created_at", { ascending: false }).limit(5),
  ]);
  const m = (metrics || {}) as any;

  return <div className="space-y-6">
    <SectionHeader title="Today" body="Your practice work requiring attention across patient intake, clinical work, coding, billing, claims and revenue." />

    <section aria-label="Today summary" className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <MetricCard label="Open requests" value={String(m.appointment_requests_open ?? 0)} note="Appointment and intake requests awaiting action" />
      <MetricCard label="Open work items" value={String(m.operations_open ?? 0)} note="Owned work across PracticeCtrl workflows" />
      <MetricCard label="Claim exceptions" value={String(m.claims_exception ?? 0)} note="Rejected, partial or exception claims requiring review" />
      <MetricCard label="Invoice balance" value={money(m.invoice_balance ?? 0)} note="PracticeCtrl balance; imported PMS evidence remains separate" />
    </section>

    <section id="attention" className="grid gap-4 xl:grid-cols-[1.3fr_.7fr]">
      <article className="rounded-lg border border-[#dce3ea] bg-white">
        <div className="flex items-center justify-between gap-3 border-b border-[#e5eaf0] px-5 py-4">
          <div>
            <h2 className="text-base font-semibold text-[#051a39]">Work requiring attention</h2>
            <p className="mt-0.5 text-xs text-[#64748b]">Priority, age, ownership and next action belong here.</p>
          </div>
          <Link href="/operations" className="shrink-0 text-sm font-semibold text-[#067c80] hover:underline">Open operations →</Link>
        </div>
        <div className="divide-y divide-[#e5eaf0]">
          {(work || []).map((w: any) => <div key={w.id} className="flex flex-wrap items-start justify-between gap-3 px-5 py-4 hover:bg-[#f8fafc]">
            <div className="min-w-0">
              <p className="text-sm font-semibold text-[#12243b]">{w.title}</p>
              <p className="mt-1 text-xs leading-5 text-[#64748b]">{w.category} · due {shortDateTime(w.due_at)}{w.blocked_reason ? ` · ${w.blocked_reason}` : ""}</p>
            </div>
            <div className="flex gap-2"><StatusPill value={w.priority} /><StatusPill value={w.status} /></div>
          </div>)}
          {!(work || []).length ? <p className="px-5 py-6 text-sm text-[#64748b]">No open work items. This queue is clear.</p> : null}
        </div>
      </article>

      <article className="rounded-lg border border-[#dce3ea] bg-white">
        <div className="flex items-center justify-between gap-3 border-b border-[#e5eaf0] px-5 py-4">
          <h2 className="text-base font-semibold text-[#051a39]">Recent VeriClaim imports</h2>
          <Link href="/admin/imports" className="text-sm font-semibold text-[#067c80] hover:underline">Imports →</Link>
        </div>
        <div className="divide-y divide-[#e5eaf0]">
          {(imports || []).map((x: any) => <div key={x.id} className="px-5 py-4">
            <div className="flex items-center justify-between gap-2"><p className="text-sm font-semibold text-[#12243b]">{x.report_type}</p><StatusPill value={x.status} /></div>
            <p className="mt-1 text-xs leading-5 text-[#64748b]">{x.row_count} rows · {x.rejected_row_count} rejected · {shortDateTime(x.created_at)}</p>
          </div>)}
          {!(imports || []).length ? <p className="px-5 py-6 text-sm text-[#64748b]">No VeriClaim batch has been promoted yet.</p> : null}
        </div>
      </article>
    </section>

    <section className="rounded-lg border border-[#bfdbfe] bg-[#eff6ff] p-5 text-sm leading-6 text-[#1e3a5f]">
      <strong className="text-[#051a39]">System boundary:</strong> VeriClaim source evidence remains immutable and separate from PracticeCtrl-created invoices and receipts. The PMS remains the appointment diary. Code10 remains clinician-confirmed decision support.
    </section>
  </div>;
}
