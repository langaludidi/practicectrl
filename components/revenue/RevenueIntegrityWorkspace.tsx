"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { WorkItemActions } from "@/components/operations/WorkItemActions";

type Finding = { severity?: string; code?: string; message?: string };
type Row = {
  invoice_id:string; invoice_number:string; patient_id:string|null; patient_name:string|null; invoice_date:string;
  total_amount:number; balance_amount:number; scheme_portion:number; status:string; score:number; blocking_count:number;
  warning_count:number; findings:Finding[]; assessed_at:string; work_item_id:string|null; work_status:string|null;
  owner_user_id:string|null; due_at:string|null;
};
type Claim = { id:string; invoice_id:string|null; claim_status:string; latest_tracking_number:string|null };

function resolutionFor(f:Finding,row:Row){
  const code=(f.code||"").toUpperCase(); const message=(f.message||"").toLowerCase();
  if(code==="MEMBERSHIP_UNVERIFIED"||message.includes("membership")) return {label:"Verify scheme membership",href:row.patient_id?`/patients/${row.patient_id}?from=integrity&invoice=${row.invoice_id}#scheme-membership`:"/patients"};
  if(code==="AUTHORISATION_INVALID"||message.includes("authorisation")) return {label:"Review authorisation",href:row.patient_id?`/authorisations?patient=${row.patient_id}&from=integrity`:"/authorisations"};
  if(code==="LIABILITY_SPLIT"||code==="NEGATIVE_BALANCE"||code==="INVALID_AMOUNT") return {label:"Review invoice",href:`/billing?invoice=${row.invoice_id}&from=integrity`};
  if(code==="LINE_COMPLETENESS"||message.includes("diagnosis")||message.includes("procedure")) return {label:"Fix coding / invoice line",href:`/billing?invoice=${row.invoice_id}&from=integrity`};
  if(message.includes("production claim route")||message.includes("accredited executable")) return {label:"Review claim integration",href:"/claims"};
  if(message.includes("sama ccsa")||message.includes("ndoh mit")||message.includes("source")) return {label:"Review governed coding evidence",href:"/claims"};
  if(code==="CLAIM_LINK"||code==="SUBMISSION_READINESS") return {label:"Review claim",href:`/claims?invoice=${row.invoice_id}&from=integrity`};
  return {label:"Review invoice and claim",href:`/billing?invoice=${row.invoice_id}&from=integrity`};
}

function whyItMatters(f:Finding){
  const code=(f.code||"").toUpperCase(); const message=(f.message||"").toLowerCase();
  if(code==="MEMBERSHIP_UNVERIFIED"||message.includes("membership")) return "The scheme portion cannot be trusted until membership is verified for the service date.";
  if(code==="AUTHORISATION_INVALID"||message.includes("authorisation")) return "A missing, expired or mismatched authorisation can cause avoidable rejection or patient liability.";
  if(code==="LINE_COMPLETENESS"||message.includes("diagnosis")||message.includes("procedure")) return "The claim line is incomplete or clinically/coding-wise unsupported, so it should be corrected before submission.";
  if(code==="LIABILITY_SPLIT"||code==="NEGATIVE_BALANCE"||code==="INVALID_AMOUNT") return "The financial values do not reconcile cleanly and could create an incorrect claim or patient balance.";
  if(message.includes("production claim route")||message.includes("accredited executable")) return "PracticeCtrl has no governed production route for this payer yet, so submission must remain blocked rather than simulated.";
  if(message.includes("sama ccsa")||message.includes("ndoh mit")||message.includes("source")) return "The claim depends on governed coding/tariff evidence that is not currently available or active.";
  return "This exception can prevent payment, create rework or compromise the integrity of the claim.";
}

export function RevenueIntegrityWorkspace({rows,claims}:{rows:Row[];claims:Claim[]}){
  const supabase=useMemo(()=>createClient(),[]); const[busy,setBusy]=useState<string|null>(null); const[message,setMessage]=useState<string|null>(null);
  const claimByInvoice=useMemo(()=>new Map(claims.filter(c=>c.invoice_id).map(c=>[c.invoice_id as string,c])),[claims]);

  async function reassess(row:Row){setBusy(row.invoice_id);setMessage(null);const claim=claimByInvoice.get(row.invoice_id);const{data,error}=await supabase.rpc("reassess_revenue_integrity",{p_invoice_id:row.invoice_id,p_claim_id:claim?.id||null});setBusy(null);if(error)setMessage(error.message);else{setMessage(`Reassessed ${row.invoice_number}: ${data?.status||"complete"}, score ${data?.score??"—"}/100.`);window.location.reload();}}
  async function prepare(row:Row){setBusy(row.invoice_id);setMessage(null);const{data,error}=await supabase.rpc("prepare_claim_from_invoice",{p_invoice_id:row.invoice_id});setBusy(null);if(error)setMessage(error.message);else{setMessage(`Claim prepared: ${data}`);window.location.reload();}}
  async function authorise(row:Row,claim:Claim){setBusy(row.invoice_id);setMessage(null);const{data,error}=await supabase.rpc("authorise_claim_submission",{p_claim_id:claim.id});setBusy(null);if(error)setMessage(error.message);else{setMessage(`Claim ${claim.latest_tracking_number||claim.id.slice(0,8)} passed Revenue Integrity at ${data?.score??"—"}/100 and is ready for the submission route.`);window.location.reload();}}

  return <div className="space-y-4">
    {message?<div className="rounded-xl border border-stone-200 bg-white p-3 text-sm text-stone-700 shadow-sm">{message}</div>:null}
    <div className="grid gap-4">{rows.map(row=>{const claim=claimByInvoice.get(row.invoice_id);const findings=Array.isArray(row.findings)?row.findings:[];return <article key={row.invoice_id} className={`rounded-2xl border bg-white shadow-sm ${row.status==="blocked"?"border-rose-200":row.status==="review"?"border-amber-200":"border-emerald-200"}`}>
      <div className="flex flex-col gap-4 border-b border-stone-100 p-5 lg:flex-row lg:items-start lg:justify-between">
        <div><div className="flex flex-wrap items-center gap-2"><h3 className="font-semibold text-[#4a1f3e]">{row.invoice_number}</h3><span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${row.status==="blocked"?"bg-rose-50 text-rose-800":row.status==="review"?"bg-amber-50 text-amber-800":"bg-emerald-50 text-emerald-800"}`}>{row.status}</span><span className="rounded-full bg-stone-100 px-2.5 py-1 text-xs font-medium text-stone-700">Integrity {row.score}/100</span></div><p className="mt-1 text-sm text-stone-600">{row.patient_name||"Patient not linked"} · {row.blocking_count} blocker(s) · {row.warning_count} warning(s)</p><p className="mt-1 text-xs text-stone-500">Outstanding R{Number(row.balance_amount||0).toFixed(2)} · scheme exposure R{Number(row.scheme_portion||0).toFixed(2)}</p></div>
        <div className="flex flex-wrap gap-2"><button type="button" disabled={busy===row.invoice_id} onClick={()=>reassess(row)} className="rounded-xl border border-stone-300 px-3 py-2 text-xs font-medium hover:bg-stone-50 disabled:opacity-50">{busy===row.invoice_id?"Working…":"Reassess"}</button>{row.status==="ready"&&!claim?<button type="button" disabled={busy===row.invoice_id} onClick={()=>prepare(row)} className="rounded-xl bg-[#4a1f3e] px-3 py-2 text-xs font-medium text-white disabled:opacity-50">Prepare claim</button>:null}{row.status==="ready"&&claim&&claim.claim_status!=="ready"?<button type="button" disabled={busy===row.invoice_id} onClick={()=>authorise(row,claim)} className="rounded-xl bg-[#4a1f3e] px-3 py-2 text-xs font-medium text-white disabled:opacity-50">Continue claim</button>:null}{claim?<Link href="/claims" className="rounded-xl border border-stone-300 px-3 py-2 text-xs font-medium hover:bg-stone-50">Open claim</Link>:null}</div>
      </div>
      <div className="grid gap-4 p-5 xl:grid-cols-[1fr_230px]">
        <div><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">What will stop us getting paid?</p><div className="mt-3 grid gap-2">{findings.length?findings.map((f,i)=>{const fix=resolutionFor(f,row);return <div key={`${f.code||"finding"}-${i}`} className="flex flex-col gap-2 rounded-xl bg-stone-50 p-3 sm:flex-row sm:items-center sm:justify-between"><div><p className="text-sm font-medium text-stone-900">{f.message||"Review required"}</p><p className="mt-1 text-xs text-stone-600">{whyItMatters(f)}</p><p className="mt-1 text-[11px] uppercase tracking-wide text-stone-500">{f.severity||"review"} · {f.code||"INTEGRITY"}</p></div><Link href={fix.href} className="shrink-0 rounded-lg border border-stone-300 bg-white px-2.5 py-1.5 text-xs font-medium hover:bg-stone-50">{fix.label}</Link></div>}):<div className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">No current blockers. The transaction can move to the next governed claim step.</div>}</div></div>
        <aside className="rounded-xl border border-stone-200 p-3"><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Exception ownership</p><p className="mt-2 text-sm font-medium">{row.work_item_id?(row.owner_user_id?"Assigned":"Unassigned"):"No open exception"}</p><p className="mt-1 text-xs text-stone-500">{row.work_status?`Status: ${row.work_status}`:"Ready assessments close the exception automatically."}</p>{row.work_item_id?<div className="mt-3"><WorkItemActions id={row.work_item_id} status={row.work_status||"open"} owned={Boolean(row.owner_user_id)}/></div>:null}</aside>
      </div>
    </article>})}{!rows.length?<div className="rounded-2xl border border-stone-200 bg-white p-6 text-sm text-stone-500 shadow-sm">No Revenue Integrity assessments yet. Finalised scheme invoices will enter this workspace when assessed or prepared for claim.</div>:null}</div>
  </div>;
}
