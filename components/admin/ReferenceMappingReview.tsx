"use client";
import {useMemo,useState} from "react";
import {createClient} from "@/lib/supabase/client";

type Mapping={mapping_id:string;provider_id:string;source_dataset_id:string;dataset:string;record_type:string;external_key:string;canonical_table:string;canonical_id:string;mapping_status:string;canonical_label:string|null};
type Review={provider_id:string;provider_slug:string;can_manage:boolean;confirmed:number;proposed:number;rejected:number;staged_mapping_required:number;queue:Mapping[]};

export function ReferenceMappingReview({data}:{data:Review|null}){
 const supabase=useMemo(()=>createClient(),[]);const[busy,setBusy]=useState<string|null>(null);const[msg,setMsg]=useState<string|null>(null);
 if(!data)return null;
 async function review(id:string,decision:"confirm"|"reject"){
  if(decision==="confirm"&&!window.confirm("Confirm this external identifier → canonical PracticeCtrl mapping?"))return;
  const notes=decision==="reject"?(window.prompt("Reason for rejecting this mapping")||""):null;
  if(decision==="reject"&&!String(notes||"").trim()){setMsg("A rejection reason is required.");return;}
  setBusy(id);setMsg(null);
  const{error}=await supabase.rpc("review_reference_entity_mapping",{p_mapping_id:id,p_decision:decision,p_notes:notes});
  setBusy(null);if(error)setMsg(error.message);else window.location.reload();
 }
 return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
  <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-[.14em] text-[#25A6A1]">External identifier governance</p><h2 className="mt-1 text-lg font-semibold text-[#173B5E]">Medprax → PracticeCtrl mapping review</h2><p className="mt-2 max-w-4xl text-sm text-stone-600">Vendor identifiers are staged first. Deterministic candidates can be proposed from CMS registration numbers and normalized names, but only a confirmed mapping can become trusted reference identity.</p></div><div className="grid grid-cols-3 gap-2 text-center text-xs"><Metric label="Confirmed" value={data.confirmed}/><Metric label="Proposed" value={data.proposed}/><Metric label="Needs mapping" value={data.staged_mapping_required}/></div></div>
  {!data.can_manage?<p className="mt-4 rounded-xl bg-stone-50 p-3 text-sm text-stone-600">Mapping detail is restricted to platform operators. Practice administrators can see readiness counts without being able to alter the canonical master.</p>:null}
  {data.can_manage&&data.queue.length?<div className="mt-4 overflow-x-auto"><table className="min-w-full text-left text-sm"><thead><tr className="border-b text-xs uppercase tracking-wide text-stone-500"><th className="px-2 py-2">Dataset</th><th className="px-2 py-2">External key</th><th className="px-2 py-2">Canonical match</th><th className="px-2 py-2">State</th><th className="px-2 py-2">Review</th></tr></thead><tbody>{data.queue.map(m=><tr key={m.mapping_id} className="border-b border-stone-100"><td className="px-2 py-3"><p className="font-medium text-stone-800">{m.record_type}</p><p className="text-xs text-stone-500">{m.dataset}</p></td><td className="px-2 py-3 font-mono text-xs">{m.external_key}</td><td className="px-2 py-3"><p>{m.canonical_label||m.canonical_id}</p><p className="text-xs text-stone-500">{m.canonical_table}</p></td><td className="px-2 py-3">{m.mapping_status}</td><td className="px-2 py-3">{m.mapping_status==="proposed"?<div className="flex gap-2"><button disabled={busy===m.mapping_id} onClick={()=>review(m.mapping_id,"confirm")} className="rounded-lg bg-[#173B5E] px-2.5 py-1.5 text-xs text-white disabled:opacity-50">Confirm</button><button disabled={busy===m.mapping_id} onClick={()=>review(m.mapping_id,"reject")} className="rounded-lg border border-stone-300 px-2.5 py-1.5 text-xs disabled:opacity-50">Reject</button></div>:<span className="text-xs text-stone-500">Human confirmed</span>}</td></tr>)}</tbody></table></div>:null}
  {data.can_manage&&!data.queue.length?<p className="mt-4 rounded-xl bg-stone-50 p-3 text-sm text-stone-600">No Medprax mapping proposals exist yet. This is expected until licensed sync credentials are configured and a governed sync run has staged records.</p>:null}
  {msg?<p className="mt-3 rounded-lg bg-stone-50 p-3 text-xs text-stone-700">{msg}</p>:null}
 </section>
}
function Metric({label,value}:{label:string;value:number}){return <div className="rounded-lg bg-stone-50 px-3 py-2"><p className="font-semibold text-[#173B5E]">{value}</p><p className="text-stone-500">{label}</p></div>}
