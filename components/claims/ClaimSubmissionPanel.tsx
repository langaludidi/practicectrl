"use client";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
type Claim={id:string;claim_status:string;latest_tracking_number:string|null;invoice_id:string|null};
export function ClaimSubmissionPanel({claims}:{claims:Claim[]}){
 const supabase=useMemo(()=>createClient(),[]);const[busy,setBusy]=useState<string|null>(null);const[results,setResults]=useState<Record<string,any>>({});const[message,setMessage]=useState<string|null>(null);
 async function assess(c:Claim){
  if(!c.invoice_id)return;setBusy(c.id);setMessage(null);
  const [integrity,contract]=await Promise.all([
    supabase.rpc("assess_revenue_integrity",{p_invoice_id:c.invoice_id,p_claim_id:c.id,p_persist:false}),
    supabase.rpc("assess_claim_contract_requirements",{p_claim_id:c.id})
  ]);
  setBusy(null);
  if(integrity.error||contract.error){setResults(x=>({...x,[c.id]:{status:"blocked",score:0,findings:[{message:integrity.error?.message||contract.error?.message}]}}));return;}
  const i:any=integrity.data||{};const p:any=contract.data||{};
  const ready=i.status==="ready"&&p.status==="ready";
  setResults(x=>({...x,[c.id]:{status:ready?"ready":(i.status==="blocked"||p.status==="blocked"?"blocked":"review"),score:i.score??0,findings:[...(i.findings||[]),...(p.findings||[])],payerContract:p}}));
 }
 async function authorise(c:Claim){setBusy(c.id);setMessage(null);const{data,error}=await supabase.rpc("authorise_claim_submission",{p_claim_id:c.id});setBusy(null);if(error)setMessage(error.message);else{setMessage(`Claim passed payer-contract and Revenue Integrity gates at ${data?.score??"—"}/100 and is ready for the accredited submission route.`);window.location.reload();}}
 return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Claim submission pre-flight</h3><p className="mt-1 text-sm text-stone-500">Immediately before submission, PracticeCtrl rechecks membership, coding evidence, payer-contract requirements, modifiers, authorisation, exclusions, frequency rules and the accredited production route. A draft claim cannot be marked ready while a blocker remains.</p>{message?<p className="mt-3 rounded-xl bg-stone-50 p-3 text-sm text-stone-700">{message}</p>:null}<div className="mt-4 grid gap-3">{claims.map(c=>{const r=results[c.id];const ready=r?.status==="ready";return <div key={c.id} className="rounded-xl border border-stone-200 p-4"><div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-sm font-medium">{c.latest_tracking_number||c.id.slice(0,8)} · {c.claim_status}</p><p className="mt-1 text-xs text-stone-500">{c.invoice_id?`Invoice ${c.invoice_id.slice(0,8)}`:"Invoice link missing"}</p></div><div className="flex gap-2"><button type="button" disabled={busy===c.id||!c.invoice_id} onClick={()=>assess(c)} className="rounded-lg border border-stone-300 px-3 py-1.5 text-xs">{busy===c.id?"Checking…":"Run submission pre-flight"}</button>{ready&&c.claim_status!=="ready"?<button type="button" disabled={busy===c.id} onClick={()=>authorise(c)} className="rounded-lg bg-[#4a1f3e] px-3 py-1.5 text-xs text-white">Authorise for submission</button>:null}</div></div>{r?<div className={`mt-3 rounded-xl p-3 text-xs ${ready?"bg-emerald-50 text-emerald-800":r.status==="review"?"bg-amber-50 text-amber-900":"bg-rose-50 text-rose-900"}`}><p className="font-semibold">{ready?`Ready · integrity ${r.score}/100`:r.status==="review"?`Review required · integrity ${r.score}/100`:`Blocked · integrity ${r.score??0}/100`}</p>{r.payerContract?<p className="mt-1">Payer contract: {r.payerContract.blocking_count||0} blocker(s), {r.payerContract.warning_count||0} warning(s).</p>:null}{r.findings?.length?<ul className="mt-2 list-disc space-y-1 pl-5">{r.findings.map((x:any,i:number)=><li key={i}>{x.code?<span className="font-medium">{x.code}: </span>:null}{x.message||String(x)}</li>)}</ul>:null}</div>:null}</div>})}{!claims.length?<p className="text-sm text-stone-500">No prepared claims exist yet.</p>:null}</div></section>
}
