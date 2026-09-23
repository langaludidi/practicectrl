"use client";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Readiness={ready?:boolean;blockers?:Array<{code?:string;message?:string}>;model_id?:string|null};
type Result={answer?:{answer?:string;findings?:Array<{statement:string;evidence_refs?:string[];metric_context?:string|null}>;caveats?:string[];suggested_drills?:Array<{label:string}>};error?:string;code?:string;needs_resolution?:boolean;unresolved?:Record<string,unknown>};

export function EconomicsInvestigator({practiceId,readiness}:{practiceId:string;readiness:Readiness}){
  const supabase=useMemo(()=>createClient(),[]);
  const[question,setQuestion]=useState("");
  const[busy,setBusy]=useState(false);
  const[result,setResult]=useState<Result|null>(null);
  async function ask(){
    const q=question.trim(); if(q.length<3)return;
    setBusy(true);setResult(null);
    const{data,error}=await supabase.functions.invoke("practicectrl-economics-investigator",{body:{question:q},headers:{"x-practicectrl-practice-id":practiceId}});
    setBusy(false);
    if(error){setResult({error:error.message});return;}
    setResult((data||{}) as Result);
  }
  return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Financial Investigator</h3><p className="mt-1 max-w-3xl text-xs text-stone-500">Natural-language investigation over deterministic Practice Economics metrics. The model plans a bounded query, PracticeCtrl calculates the evidence, and the model may explain only those returned facts.</p></div><span className={`rounded-full px-2.5 py-1 text-xs font-medium ${readiness?.ready?"bg-emerald-50 text-emerald-700":"bg-amber-50 text-amber-800"}`}>{readiness?.ready?"Governed AI ready":"Governed AI blocked"}</span></div>
    {!readiness?.ready?<div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900"><p className="font-medium">Financial Investigator remains fail-closed.</p><div className="mt-1 grid gap-1 text-xs">{(readiness?.blockers||[]).map((b,i)=><p key={`${b.code||"block"}-${i}`}>{b.message||b.code}</p>)}{!(readiness?.blockers||[]).length?<p>A PHI-approved provider policy has not been activated for this practice.</p>:null}</div></div>:null}
    <div className="mt-4 grid gap-3"><textarea value={question} onChange={(e:React.ChangeEvent<HTMLTextAreaElement>)=>setQuestion(e.target.value)} disabled={!readiness?.ready||busy} rows={3} placeholder="Why did realised revenue per RVU fall this month?" className="w-full rounded-xl border border-stone-300 bg-white px-3 py-2 text-sm outline-none focus:border-[#4a1f3e] disabled:bg-stone-50"/><div><button type="button" onClick={ask} disabled={!readiness?.ready||busy||question.trim().length<3} className="rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{busy?"Investigating…":"Investigate"}</button></div></div>
    {result?.error?<p className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-800">{result.error}{result.code?` (${result.code})`:""}</p>:null}
    {result?.needs_resolution?<div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900"><p className="font-medium">A named scheme, plan, practitioner or location is ambiguous.</p><pre className="mt-2 overflow-auto whitespace-pre-wrap text-xs">{JSON.stringify(result.unresolved,null,2)}</pre></div>:null}
    {result?.answer?.answer?<div className="mt-5 space-y-4"><div className="rounded-xl bg-stone-50 p-4 text-sm leading-6 text-stone-800">{result.answer.answer}</div>{result.answer.findings?.length?<div><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Evidence-backed findings</p><div className="mt-2 grid gap-2">{result.answer.findings.map((f,i)=><div key={i} className="rounded-xl border border-stone-200 p-3 text-sm"><p>{f.statement}</p>{f.metric_context?<p className="mt-1 text-xs text-stone-500">{f.metric_context}</p>:null}{f.evidence_refs?.length?<p className="mt-1 text-[11px] text-stone-400">{f.evidence_refs.join(" · ")}</p>:null}</div>)}</div></div>:null}{result.answer.caveats?.length?<div className="rounded-xl border border-stone-200 p-3 text-xs text-stone-600"><p className="font-semibold">Caveats</p>{result.answer.caveats.map((c,i)=><p key={i} className="mt-1">{c}</p>)}</div>:null}</div>:null}
  </section>;
}
