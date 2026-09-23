"use client";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Invoice={id:string;invoice_number:string;status:string;medical_scheme_id:string|null};
type Validation={id:string;invoice_id:string;invoice_line_id:string|null;rule_code:string;severity:string;message:string;status:string;created_at:string};

export function ClaimPreflightPanel({invoices,validations}:{invoices:Invoice[];validations:Validation[]}){
  const supabase=useMemo(()=>createClient(),[]);
  const [busy,setBusy]=useState<string|null>(null);
  const [results,setResults]=useState<Record<string,any>>({});
  const [message,setMessage]=useState<string|null>(null);
  const drafts=invoices.filter(i=>i.status==="draft"&&i.medical_scheme_id);

  async function run(invoice:Invoice){
    setBusy(invoice.id);setMessage(null);
    const {data,error}=await supabase.rpc("run_invoice_claim_preflight",{p_invoice_id:invoice.id,p_persist:true});
    setBusy(null);
    if(error){setMessage(error.message);return;}
    setResults(x=>({...x,[invoice.id]:data}));
  }

  return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h3 className="font-semibold text-[#4a1f3e]">Automated claim pre-flight</h3><p className="mt-1 max-w-3xl text-sm text-stone-500">PracticeCtrl now resolves effective payer-contract rates automatically and checks verified membership, modifiers, authorisation, referrals, frequency limits, exclusions, balance-billing restrictions and contractual tariff amounts before finalisation.</p></div>
      <span className="rounded-full bg-stone-100 px-3 py-1 text-xs text-stone-600">Finalisation gate</span>
    </div>
    {message?<p className="mt-3 rounded-xl bg-rose-50 p-3 text-sm text-rose-900">{message}</p>:null}
    <div className="mt-4 grid gap-3">
      {drafts.map(inv=>{const r=results[inv.id];const existing=validations.filter(v=>v.invoice_id===inv.id&&v.status!=="resolved");return <div key={inv.id} className="rounded-xl border border-stone-200 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3"><div><p className="text-sm font-medium">{inv.invoice_number}</p><p className="mt-1 text-xs text-stone-500">{existing.length?`${existing.length} current pre-flight finding(s)`:`No open automated pre-flight findings`}</p></div><button type="button" disabled={busy===inv.id} onClick={()=>run(inv)} className="rounded-lg bg-[#4a1f3e] px-3 py-2 text-xs font-medium text-white disabled:opacity-50">{busy===inv.id?"Running…":"Run pre-flight"}</button></div>
        {r?<div className={`mt-3 rounded-xl p-3 text-xs ${r.status==="ready"?"bg-emerald-50 text-emerald-900":r.status==="review"?"bg-amber-50 text-amber-900":"bg-rose-50 text-rose-900"}`}><p className="font-semibold">{r.status==="ready"?"Ready":r.status==="review"?"Review required":"Blocked"} · {r.blocking_count||0} blocker(s) · {r.warning_count||0} warning(s)</p><p className="mt-1">Automatic contract resolution: {r.auto_resolution?.resolved||0} updated, {r.auto_resolution?.skipped||0} current/not applicable, {r.auto_resolution?.blocked||0} unresolved.</p>{r.findings?.length?<ul className="mt-2 list-disc space-y-1 pl-5">{r.findings.map((f:any,n:number)=><li key={n}><span className="font-medium">{f.code||"PREFLIGHT"}</span>{f.line_no?` · line ${f.line_no}`:""}: {f.message}</li>)}</ul>:<p className="mt-2">All configured payer-contract gates passed.</p>}</div>:null}
        {!r&&existing.length?<div className="mt-3 grid gap-1">{existing.slice(0,6).map(v=><p key={v.id} className={`rounded-lg px-2.5 py-2 text-xs ${v.severity==="blocking"?"bg-rose-50 text-rose-900":"bg-amber-50 text-amber-900"}`}><span className="font-medium">{v.rule_code}</span>: {v.message}</p>)}</div>:null}
      </div>})}
      {!drafts.length?<p className="text-sm text-stone-500">No draft scheme-funded invoices are awaiting pre-flight.</p>:null}
    </div>
  </section>;
}
