"use client";

import { ChangeEvent, FormEvent, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Document={id:string;title:string;document_type:string;review_status:string;extraction_status:string;proposed_terms:Record<string,unknown>|null};

export function ContractIntelligencePanel({documents,canManage}:{documents:Document[];canManage:boolean}){
  const supabase=useMemo(()=>createClient(),[]);
  const[documentId,setDocumentId]=useState(documents.find(d=>d.review_status!=="approved")?.id||"");
  const[busy,setBusy]=useState(false);const[msg,setMsg]=useState<string|null>(null);const[err,setErr]=useState<string|null>(null);
  const selected=documents.find(d=>d.id===documentId);
  async function save(e:FormEvent<HTMLFormElement>){
    e.preventDefault();setBusy(true);setMsg(null);setErr(null);const fd=new FormData(e.currentTarget);
    const number=(name:string)=>{const v=String(fd.get(name)||"").trim();return v===""?null:Number(v)};
    const terms={
      proposal_source:"human_assisted",
      tariff_basis:String(fd.get("tariff_basis")||"").trim()||null,
      negotiated_rate_percent:number("negotiated_rate_percent"),
      network_status:String(fd.get("network_status")||"").trim()||null,
      payment_terms_days:number("payment_terms_days"),
      submission_window_days:number("submission_window_days"),
      authorisation_summary:String(fd.get("authorisation_summary")||"").trim()||null,
      referral_summary:String(fd.get("referral_summary")||"").trim()||null,
      balance_billing_summary:String(fd.get("balance_billing_summary")||"").trim()||null,
      exclusions_summary:String(fd.get("exclusions_summary")||"").trim()||null,
      reviewer_notes:String(fd.get("reviewer_notes")||"").trim()||null,
    };
    const {error}=await supabase.rpc("propose_payer_contract_document_terms",{p_document_id:documentId,p_terms:terms});
    setBusy(false);if(error){setErr(error.message);return;}setMsg("Structured terms recorded for human review. Nothing has been activated.");window.setTimeout(()=>window.location.reload(),600);
  }
  if(!canManage)return null;
  return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Contract intelligence review</h3><p className="mt-1 max-w-3xl text-sm text-stone-500">Capture structured terms extracted from the agreement. These remain proposals until evidence and the contract are separately approved. This gives the later AI extraction adapter a governed target schema without allowing AI to activate billing rules.</p></div><span className="rounded-full bg-violet-50 px-3 py-1 text-xs font-medium text-violet-800">Human approval required</span></div>
    {!documents.length?<p className="mt-4 text-sm text-stone-500">Upload payer agreement evidence first.</p>:<form onSubmit={save} className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <select value={documentId} onChange={(e:ChangeEvent<HTMLSelectElement>)=>setDocumentId(e.target.value)} required className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2 xl:col-span-4"><option value="">Select agreement evidence</option>{documents.map(d=><option key={d.id} value={d.id}>{d.title} · {d.review_status} · extraction {d.extraction_status}</option>)}</select>
      <input name="tariff_basis" placeholder="Tariff basis e.g. scheme tariff" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="negotiated_rate_percent" type="number" min="0" step="0.01" placeholder="Negotiated % e.g. 110" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <select name="network_status" defaultValue="" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">Network status</option><option value="contracted">Contracted</option><option value="preferred">Preferred provider</option><option value="dsp">DSP</option><option value="non_network">Non-network</option></select>
      <input name="payment_terms_days" type="number" min="0" placeholder="Payment terms days" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="submission_window_days" type="number" min="0" placeholder="Claim submission window days" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="authorisation_summary" placeholder="Authorisation requirements" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="referral_summary" placeholder="Referral requirements" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="balance_billing_summary" placeholder="Co-pay / balance billing rule" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <textarea name="exclusions_summary" placeholder="Exclusions / special billing clauses" className="min-h-20 rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/>
      <textarea name="reviewer_notes" placeholder="Extraction / reviewer notes" className="min-h-20 rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/>
      <button disabled={busy||!documentId||selected?.review_status==="approved"} className="rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50 sm:col-span-2 xl:col-span-1">{busy?"Saving…":"Save proposed terms"}</button>
      {selected?.review_status==="approved"?<p className="self-center text-xs text-amber-700 sm:col-span-2 xl:col-span-3">Approved evidence is locked. Upload a new agreement version before changing extracted terms.</p>:null}
    </form>}
    {err?<p role="alert" className="mt-3 rounded-xl bg-rose-50 p-3 text-sm text-rose-800">{err}</p>:null}{msg?<p role="status" className="mt-3 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{msg}</p>:null}
    {selected?.proposed_terms&&Object.keys(selected.proposed_terms).length?<details className="mt-4 rounded-xl border border-stone-200 bg-stone-50 p-3"><summary className="cursor-pointer text-sm font-medium text-stone-700">Current structured proposal</summary><pre className="mt-3 overflow-x-auto whitespace-pre-wrap text-xs text-stone-600">{JSON.stringify(selected.proposed_terms,null,2)}</pre></details>:null}
  </section>;
}
