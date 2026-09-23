import Link from "next/link";
import { MetricCard } from "@/components/MetricCard";
import { money } from "@/lib/format";

function num(v:any,d=0){const n=Number(v);return Number.isFinite(n)?n:d;}
function pct(v:any){return v===null||v===undefined?"—":`${num(v).toFixed(1)}%`;}
function unit(v:any){return v===null||v===undefined?"—":num(v).toLocaleString("en-ZA",{maximumFractionDigits:2});}
function rpu(v:any){return v===null||v===undefined?"—":`${money(v)}/unit`;}

type SliceRow={dimensions:Record<string,any>;metrics:Record<string,any>};
function EconomicsTable({title,rows,kind}:{title:string;rows:SliceRow[];kind:"scheme"|"plan"|"procedure"}){
  const label=(r:SliceRow)=>kind==="scheme"?(r.dimensions.scheme_name||"Private / self-pay"):kind==="plan"?`${r.dimensions.scheme_name||"—"} · ${r.dimensions.plan_name||"No plan"}`:`${r.dimensions.procedure_code||"—"} · ${r.dimensions.procedure_name||""}`;
  return <article className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm"><div className="border-b border-stone-100 px-5 py-4"><h3 className="font-semibold text-[#4a1f3e]">{title}</h3></div><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="bg-stone-50 text-xs text-stone-500"><tr><th className="px-4 py-3">{kind==="procedure"?"Procedure":kind==="plan"?"Scheme / plan":"Scheme"}</th><th className="px-4 py-3">Units</th><th className="px-4 py-3">RVU share</th><th className="px-4 py-3">Expected/unit</th><th className="px-4 py-3">Actual/unit</th><th className="px-4 py-3">Realisation</th><th className="px-4 py-3">Unrealised</th><th className="px-4 py-3">Recoverable</th></tr></thead><tbody>{rows.slice(0,12).map((r,i)=><tr key={`${label(r)}-${i}`} className="border-t border-stone-100"><td className="px-4 py-3 font-medium">{label(r)}</td><td className="px-4 py-3">{unit(r.metrics.total_units)}</td><td className="px-4 py-3">{pct(r.metrics.rvu_contribution_pct)}</td><td className="px-4 py-3">{rpu(r.metrics.expected_revenue_per_unit)}</td><td className="px-4 py-3">{rpu(r.metrics.actual_revenue_per_unit)}</td><td className="px-4 py-3">{pct(r.metrics.rvu_realisation_rate_pct)}</td><td className="px-4 py-3">{money(r.metrics.unrealised_expected_value)}</td><td className="px-4 py-3">{money(r.metrics.recoverable_leakage)}</td></tr>)}</tbody></table></div>{!rows.length?<p className="p-5 text-sm text-stone-500">No economics lines are available for this period yet.</p>:null}</article>;
}

export function PracticeEconomicsDashboard({overview,scheme,plan,procedure,waterfall,productivity}:{overview:any;scheme:any;plan:any;procedure:any;waterfall:any;productivity:any}){
  const m=overview?.metrics||{}; const costAllowed=Boolean(overview?.cost_metrics_allowed);
  const cards=[
    ["Total RVUs / IRUs",unit(m.total_units),`${m.unit_unresolved_lines||0} unresolved line(s)`],
    ["Expected revenue / unit",rpu(m.expected_revenue_per_unit),"Contractual expected recoverable value"],
    ["Actual revenue / unit",rpu(m.actual_revenue_per_unit),"Scheme + patient collections"],
    ["RVU realisation",pct(m.rvu_realisation_rate_pct),"Realised ÷ expected value"],
    ["Expected revenue",money(m.expected_revenue),"Expected scheme + patient responsibility"],
    ["Realised revenue",money(m.realised_revenue),"Cash/posted collections represented in the ledger"],
    ["Unrealised expected value",money(m.unrealised_expected_value),"Not all unrealised value is recoverable"],
    ["Recoverable value",money(m.amount_recoverable),"Open cases classified recoverable / possibly recoverable"]
  ];
  if(costAllowed)cards.push(["Contribution margin",m.contribution_margin===null?"—":money(m.contribution_margin),`Cost coverage ${pct(m.cost_coverage_pct)}`]);
  const stages=(waterfall?.stages||[]) as any[];
  return <div className="space-y-6">
    <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">{cards.map(([label,value,note])=><div key={label}><MetricCard label={label} value={value} note={note}/></div>)}</section>
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-stone-200 bg-white p-4 shadow-sm"><div><p className="font-medium text-[#4a1f3e]">From variance to recovery</p><p className="mt-1 text-sm text-stone-600">Practice Economics explains the variance; Recovery Workbench controls the governed follow-through.</p></div><Link href="/recovery" className="rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white">Open Recovery Workbench</Link></div>
    <section className="grid gap-4 xl:grid-cols-2"><EconomicsTable title="Payer performance" rows={(scheme?.rows||[]) as SliceRow[]} kind="scheme"/><EconomicsTable title="Plan performance" rows={(plan?.rows||[]) as SliceRow[]} kind="plan"/></section>
    <EconomicsTable title="Procedure performance" rows={(procedure?.rows||[]) as SliceRow[]} kind="procedure"/>
    <section className="grid gap-4 xl:grid-cols-[1.1fr_.9fr]"><article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Revenue waterfall</h3><p className="mt-1 text-xs text-stone-500">Where value moves from charges through expected reimbursement to realised collections.</p><div className="mt-4 grid gap-2">{stages.map((s:any)=><div key={s.key} className="flex items-center justify-between gap-3 rounded-xl bg-stone-50 px-3 py-2"><div><p className="text-sm font-medium">{s.label}</p><p className="text-xs text-stone-500">{rpu(s.rand_per_unit)}</p></div><p className="text-sm font-semibold">{money(s.amount)}</p></div>)}</div></article><article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Practitioner productivity</h3><p className="mt-1 text-xs text-stone-500">Workload/economic activity only — not a clinical-quality score.</p><div className="mt-4 grid gap-3">{(productivity?.rows||[]).slice(0,10).map((r:any)=><div key={r.practitioner_user_id||r.practitioner_profile_id} className="rounded-xl border border-stone-200 p-3"><div className="flex justify-between gap-3"><p className="text-sm font-medium">{r.practitioner_name||"Practitioner"}</p><p className="text-sm font-semibold">{unit(r.total_units)} units</p></div><p className="mt-1 text-xs text-stone-500">{r.rvus_per_clinical_hour===null||r.rvus_per_clinical_hour===undefined?"Clinical time unavailable":`${unit(r.rvus_per_clinical_hour)} units/hour`} · {pct(r.realisation_rate_pct)} realised</p></div>)}{!(productivity?.rows||[]).length?<p className="text-sm text-stone-500">No practitioner economics data for this period.</p>:null}</div></article></section>
  </div>;
}
