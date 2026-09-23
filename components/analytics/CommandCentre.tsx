import Link from "next/link";
import { MetricCard } from "@/components/MetricCard";
import { StatusPill } from "@/components/StatusPill";
import { money, shortDate, shortDateTime } from "@/lib/format";

type CommandCentreData = {
  generated_at?: string;
  window_days?: number;
  window_start?: string;
  role?: string;
  finance_allowed?: boolean;
  operations?: Record<string, number>;
  patient_flow?: Record<string, number>;
  coding?: Record<string, number>;
  authorisations?: Record<string, number | null>;
  revenue?: Record<string, number | null> | null;
  claims?: Record<string, number | null> | null;
  workload?: Array<{ user_id?: string | null; email: string; role: string; open_count: number; overdue_count: number; blocked_count: number }>;
  work_categories?: Array<{ category: string; count: number; overdue: number }>;
  scheme_exposure?: Array<{ scheme_name: string; invoice_balance: number; claimed: number; paid: number; claim_count: number }>;
  source_freshness?: Array<{ report_type: string; status: string; row_count: number; rejected_row_count: number; period_start?: string | null; period_end?: string | null; snapshot_at?: string | null; created_at?: string | null }>;
  patient_flow_series?: Array<{ date: string; appointments: number; completed_appointments: number; encounters: number; new_patients: number }>;
};

const n=(value:unknown)=>Number(value||0);
const pct=(value:unknown)=>value==null?"—":`${Number(value).toFixed(1)}%`;
const title=(value:string)=>value.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());

function RatioBar({value,max,label,note}:{key?:string;value:number;max:number;label:string;note?:string}){
  const width=max>0?Math.max(2,Math.min(100,(value/max)*100)):0;
  return <div>
    <div className="flex items-center justify-between gap-3 text-sm"><span className="truncate text-stone-700">{label}</span><span className="font-medium text-stone-900">{value}</span></div>
    <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-stone-100"><div className="h-full rounded-full bg-[#4a1f3e]" style={{width:`${width}%`}}/></div>
    {note?<p className="mt-1 text-xs text-stone-500">{note}</p>:null}
  </div>;
}

function MiniTrend({rows}:{rows:CommandCentreData["patient_flow_series"]}){
  const data=rows||[]; const max=Math.max(1,...data.map(x=>n(x.appointments)+n(x.encounters)+n(x.new_patients)));
  if(!data.length) return <p className="text-sm text-stone-500">No patient-flow activity in this window.</p>;
  return <div className="flex h-36 items-end gap-1 overflow-hidden pt-4" aria-label="Patient-flow activity trend">
    {data.map((x,index)=>{const total=n(x.appointments)+n(x.encounters)+n(x.new_patients);const h=Math.max(4,Math.round(total/max*100));return <div key={`${x.date}-${index}`} className="group relative flex min-w-1 flex-1 items-end" title={`${shortDate(x.date)} · ${x.appointments} appointments · ${x.encounters} encounters · ${x.new_patients} new patients`}><div className="w-full rounded-t bg-[#25A6A1]" style={{height:`${h}%`}}/></div>})}
  </div>;
}

export function CommandCentre({data}:{data:CommandCentreData}){
  const o=data.operations||{}; const flow=data.patient_flow||{}; const coding=data.coding||{}; const auth=data.authorisations||{}; const revenue=data.revenue||{}; const claims=data.claims||{};
  const workload=data.workload||[]; const categories=data.work_categories||[]; const schemes=data.scheme_exposure||[]; const freshness=data.source_freshness||[];
  const maxWork=Math.max(1,...workload.map(x=>n(x.open_count))); const maxCategory=Math.max(1,...categories.map(x=>n(x.count))); const maxScheme=Math.max(1,...schemes.map(x=>n(x.invoice_balance)));
  return <div className="space-y-6">
    <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <MetricCard label="Active patients" value={String(n(o.active_patients))} note={`${n(o.new_patients)} new in ${data.window_days||30} days`}/>
      <MetricCard label="Today's appointments" value={String(n(o.appointments_today))} note={`${n(o.appointments_upcoming_7d)} booked / confirmed next 7 days`}/>
      <MetricCard label="Open operational work" value={String(n(o.work_open))} note={`${n(o.work_overdue)} overdue · ${n(o.work_blocked)} blocked`}/>
      <MetricCard label="Coding blockers" value={String(n(coding.blocking_open))} note={`${n(coding.warnings_open)} open warnings · ${n(coding.active_authority_codes)} active authority codes`}/>
    </section>

    {data.finance_allowed?<section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
      <MetricCard label={`Billed · ${data.window_days||30}d`} value={money(n(revenue.billed))} note={`${n(revenue.invoices)} PracticeCtrl invoices`}/>
      <MetricCard label="Collected against window" value={money(n(revenue.received))} note={`${pct(revenue.collection_rate_pct)} invoice-level collection rate`}/>
      <MetricCard label="Outstanding on window invoices" value={money(n(revenue.outstanding))} note={`${money(n(revenue.overdue_balance))} overdue across active invoices`}/>
      <MetricCard label="Claims paid ratio" value={pct(claims.paid_ratio_pct)} note={`${money(n(claims.total_paid))} paid of ${money(n(claims.total_claimed))} claimed`}/>
    </section>:<section className="rounded-2xl border border-stone-200 bg-white p-5 text-sm text-stone-600 shadow-sm"><strong className="text-stone-800">Role-aware view.</strong> Financial, claims and scheme-exposure analytics are withheld for this role. Patient flow, coding quality and operational accountability remain available.</section>}

    <section className="grid gap-4 xl:grid-cols-[1.15fr_.85fr]">
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Patient flow</h3><p className="mt-1 text-xs text-stone-500">Appointments, encounters and new registrations across the selected reporting window.</p></div><Link href="/appointments" className="text-sm font-medium text-[#e5533d]">Open diary →</Link></div>
        <MiniTrend rows={data.patient_flow_series}/>
        <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><Small label="Registered" value={n(flow.registered)}/><Small label="Intakes submitted" value={n(flow.intakes_submitted)}/><Small label="Intakes applied" value={n(flow.intakes_applied)}/><Small label="Completed encounters" value={n(flow.completed_encounters)}/></div>
      </article>
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <div className="flex items-start justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Authorisation performance</h3><p className="mt-1 text-xs text-stone-500">Decisions recorded during this window; pending is current workload.</p></div><Link href="/authorisations" className="text-sm font-medium text-[#e5533d]">Open →</Link></div>
        <div className="mt-5 grid grid-cols-2 gap-3"><Small label="Requested" value={n(auth.requested)}/><Small label="Pending" value={n(auth.pending)}/><Small label="Approved" value={n(auth.approved)}/><Small label="Declined" value={n(auth.declined)}/></div>
        <div className="mt-4 rounded-xl bg-stone-50 p-4"><p className="text-xs uppercase tracking-wide text-stone-500">Decision approval rate</p><p className="mt-2 text-2xl font-semibold text-[#4a1f3e]">{pct(auth.approval_rate_pct)}</p><p className="mt-1 text-xs text-stone-500">Calculated only from approved / partially approved / declined decisions.</p></div>
      </article>
    </section>

    <section className="grid gap-4 xl:grid-cols-2">
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><div className="flex items-center justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Staff accountability</h3><p className="mt-1 text-xs text-stone-500">Open assigned work, overdue load and blocked items.</p></div><Link href="/operations" className="text-sm font-medium text-[#e5533d]">Operations →</Link></div><div className="mt-5 grid gap-4">{workload.map((x,i)=><RatioBar key={`${x.user_id||"none"}-${i}`} value={n(x.open_count)} max={maxWork} label={x.email} note={`${title(x.role)} · ${n(x.overdue_count)} overdue · ${n(x.blocked_count)} blocked`}/>)}{!workload.length?<p className="text-sm text-stone-500">No staff workload is available yet.</p>:null}</div></article>
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Work by source</h3><p className="mt-1 text-xs text-stone-500">Where unresolved workload is accumulating across PracticeCtrl modules.</p><div className="mt-5 grid gap-4">{categories.map((x,i)=><RatioBar key={`${x.category}-${i}`} value={n(x.count)} max={maxCategory} label={title(x.category)} note={`${n(x.overdue)} overdue`}/>)}{!categories.length?<p className="text-sm text-stone-500">No open cross-module work.</p>:null}</div></article>
    </section>

    <section className="grid gap-4 xl:grid-cols-2">
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><div className="flex items-center justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Code10 quality</h3><p className="mt-1 text-xs text-stone-500">Deterministic coding activity and unresolved validation findings.</p></div><Link href="/coding" className="text-sm font-medium text-[#e5533d]">Code10 →</Link></div><div className="mt-5 grid grid-cols-2 gap-3"><Small label="Sessions" value={n(coding.sessions)}/><Small label="Completed" value={n(coding.completed_sessions)}/><Small label="Final selections" value={n(coding.confirmed_decisions)}/><Small label="Open warnings" value={n(coding.warnings_open)}/></div>{n(coding.active_authority_codes)===0?<p className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs leading-5 text-amber-900">Code10 remains source-locked because no governed NDoH MIT authority rows are active. Analytics will not substitute sample or non-South-African code data.</p>:null}</article>
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Operational exceptions</h3><p className="mt-1 text-xs text-stone-500">Current queue health rather than patient-level exception detail.</p><div className="mt-5 grid grid-cols-2 gap-3"><Small label="Overdue work" value={n(o.work_overdue)}/><Small label="Blocked work" value={n(o.work_blocked)}/><Small label="Unassigned work" value={n(o.work_unassigned)}/><Small label="Pending intake review" value={n(o.intake_pending_review)}/></div><div className="mt-4 flex flex-wrap gap-2"><Link href="/operations" className="rounded-xl border border-stone-300 px-3 py-2 text-xs font-medium">Resolve operations</Link><Link href="/intake" className="rounded-xl border border-stone-300 px-3 py-2 text-xs font-medium">Review intake</Link></div></article>
    </section>

    {data.finance_allowed?<>
      <section className="grid gap-4 xl:grid-cols-[.85fr_1.15fr]">
        <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><div className="flex items-start justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Claims performance</h3><p className="mt-1 text-xs text-stone-500">PracticeCtrl claims in this reporting window.</p></div><Link href="/claims" className="text-sm font-medium text-[#e5533d]">Claims & ERA →</Link></div><div className="mt-5 grid grid-cols-2 gap-3"><Small label="Submitted" value={n(claims.submitted)}/><Small label="Clean accepted" value={n(claims.accepted)}/><Small label="Rejected" value={n(claims.rejected)}/><Small label="Exceptions" value={n(claims.exceptions)}/></div><div className="mt-4 rounded-xl bg-stone-50 p-4"><p className="text-xs uppercase tracking-wide text-stone-500">Clean acceptance</p><p className="mt-2 text-2xl font-semibold text-[#4a1f3e]">{pct(claims.clean_acceptance_pct)}</p><p className="mt-1 text-xs text-stone-500">Excludes claims with no adjudication outcome.</p></div></article>
        <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><div className="flex items-start justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Scheme exposure</h3><p className="mt-1 text-xs text-stone-500">Current PracticeCtrl invoice balance, with claims activity from the selected window.</p></div><Link href="/integrity" className="text-sm font-medium text-[#e5533d]">Revenue Integrity →</Link></div><div className="mt-5 grid gap-4">{schemes.map((x,i)=><RatioBar key={`${x.scheme_name}-${i}`} value={n(x.invoice_balance)} max={maxScheme} label={x.scheme_name} note={`${money(n(x.invoice_balance))} balance · ${money(n(x.claimed))} claimed · ${money(n(x.paid))} paid · ${n(x.claim_count)} claims`}/>)}{!schemes.length?<p className="text-sm text-stone-500">No outstanding PracticeCtrl scheme exposure yet.</p>:null}</div></article>
      </section>
      <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4"><MetricCard label="Actionable collection cases" value={String(n(revenue.actionable_collection_cases))} note={`${money(n(revenue.collection_case_exposure))} case exposure`}/><MetricCard label="Open payer variances" value={String(n(revenue.open_variances))} note={`${money(n(revenue.variance_exposure))} absolute variance exposure`}/><MetricCard label="No-shows" value={String(n(o.appointments_no_show))} note={`${n(o.appointments_cancelled)} cancellations in window`}/><MetricCard label="Completed appointments" value={String(n(o.appointments_completed))} note={`${n(o.encounters_completed)} completed encounters`}/></section>
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Imported source freshness</h3><p className="mt-1 text-xs text-stone-500">Immutable VeriClaim evidence is shown separately from PracticeCtrl transactional KPIs.</p><div className="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-3">{freshness.map((x,i)=><div key={`${x.report_type}-${i}`} className="rounded-xl border border-stone-200 p-3"><div className="flex items-start justify-between gap-2"><p className="text-sm font-medium">{title(x.report_type)}</p><StatusPill value={x.status}/></div><p className="mt-2 text-xs text-stone-500">{n(x.row_count)} rows · {n(x.rejected_row_count)} rejected</p><p className="mt-1 text-xs text-stone-500">Scope {shortDate(x.period_start)}–{shortDate(x.period_end)} · loaded {shortDateTime(x.created_at)}</p></div>)}{!freshness.length?<p className="text-sm text-stone-500">No promoted source imports yet.</p>:null}</div></article>
    </>:null}

    <section className="rounded-2xl border border-[#b7ddd9] bg-[#f2fbfa] p-5 text-sm leading-6 text-[#173B5E]"><strong>Metric boundary:</strong> PracticeCtrl transactional KPIs are calculated from PracticeCtrl records. Imported VeriClaim material remains separately identified as source evidence. Empty denominators produce “—” rather than a misleading 0% rate. Generated {shortDateTime(data.generated_at)}.</section>
  </div>;
}

function Small({label,value}:{label:string;value:string|number}){return <div className="rounded-xl border border-stone-200 bg-stone-50 p-3"><p className="text-xs text-stone-500">{label}</p><p className="mt-1 text-lg font-semibold text-stone-900">{value}</p></div>}
