"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function ClaimActions({ invoices, claims, remittanceLines }: {
  invoices:Array<{id:string;invoice_number:string;status:string}>;
  claims:Array<{id:string;claim_status:string;latest_tracking_number:string|null}>;
  remittanceLines:Array<{id:string;external_claim_ref:string|null;paid_amount:number|null;claim_id:string|null}>;
}) {
  const supabase=createClient(); const [msg,setMsg]=useState<string|null>(null); const [busy,setBusy]=useState(false);
  async function readiness(id:string){setBusy(true);const {data,error}=await supabase.rpc("assess_claim_readiness",{p_invoice_id:id});setBusy(false);setMsg(error?error.message:JSON.stringify(data));}
  async function prepare(id:string){setBusy(true);const {data,error}=await supabase.rpc("prepare_claim_from_invoice",{p_invoice_id:id});setBusy(false);if(error)setMsg(error.message);else{setMsg(`Claim draft prepared: ${data}`);window.location.reload();}}
  async function match(formData:FormData){setBusy(true);const {error}=await supabase.rpc("manual_match_remittance_line",{p_remittance_line_id:String(formData.get("lineId")),p_claim_id:String(formData.get("claimId")),p_claim_line_id:null,p_note:String(formData.get("note")||"")||null});setBusy(false);if(error)setMsg(error.message);else{setMsg("Remittance line matched. Payment remains unposted until separately allocated.");window.location.reload();}}
  return <div className="grid gap-4 xl:grid-cols-2">
    <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Claim readiness</h3><p className="mt-1 text-sm text-stone-500">Assessment is read-only. Preparing a claim is permitted only if all authoritative gates pass.</p><div className="mt-4 grid gap-2">{invoices.slice(0,8).map(i=><div key={i.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-stone-200 p-3"><span className="text-sm">{i.invoice_number} · {i.status}</span><div className="flex gap-2"><button type="button" disabled={busy} onClick={()=>readiness(i.id)} className="rounded-lg border px-2.5 py-1.5 text-xs">Assess</button><button type="button" disabled={busy} onClick={()=>prepare(i.id)} className="rounded-lg bg-[#4a1f3e] px-2.5 py-1.5 text-xs text-white">Prepare claim</button></div></div>)}</div></div>
    <form action={match} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Manual ERA match</h3><p className="mt-1 text-sm text-stone-500">Matching establishes reconciliation evidence only; it never posts cash.</p><div className="mt-4 grid gap-3"><select name="lineId" className="rounded-xl border border-stone-300 px-3 py-2 text-sm">{remittanceLines.filter(x=>!x.claim_id).map(l=><option key={l.id} value={l.id}>{l.external_claim_ref||l.id.slice(0,8)} · paid R{Number(l.paid_amount||0).toFixed(2)}</option>)}</select><select name="claimId" className="rounded-xl border border-stone-300 px-3 py-2 text-sm">{claims.map(c=><option key={c.id} value={c.id}>{c.latest_tracking_number||c.id.slice(0,8)} · {c.claim_status}</option>)}</select><input name="note" placeholder="Manual matching note" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/></div><button disabled={busy||!claims.length||!remittanceLines.some(x=>!x.claim_id)} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-40">Match line</button></form>
    {msg?<pre className="overflow-auto whitespace-pre-wrap rounded-2xl border border-stone-200 bg-stone-50 p-4 text-xs text-stone-700 xl:col-span-2">{msg}</pre>:null}
  </div>;
}
