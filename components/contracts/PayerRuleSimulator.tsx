"use client";

import { ChangeEvent, FormEvent, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Scheme={id:string;name:string};
type Option={id:string;medical_scheme_id:string;benefit_year:number;option_name:string};
type Practitioner={id:string;display_name:string};
type Result={
  matched:boolean;
  applied_rule_id:string|null;
  applied_contract_id:string|null;
  precedence_level:string|null;
  reference_amount:number|null;
  charged_amount:number|null;
  expected_contractual_amount:number|null;
  expected_scheme_amount:number|null;
  estimated_patient_liability:number|null;
  calculation_method:string|null;
  rate_percent:number|null;
  fixed_amount:number|null;
  requirements:Array<{rule_id:string;rule_type:string;requirements:Record<string,unknown>;rule_value:Record<string,unknown>;scope:string}>;
  confidence:"low"|"medium"|"high";
  source_document_id:string|null;
  effective_date:string;
};

const money=(value:number|null|undefined)=>value==null?"—":new Intl.NumberFormat("en-ZA",{style:"currency",currency:"ZAR"}).format(value);
const today=()=>new Date().toISOString().slice(0,10);

export function PayerRuleSimulator({practiceId,schemes,options,practitioners}:{practiceId:string;schemes:Scheme[];options:Option[];practitioners:Practitioner[]}){
  const supabase=useMemo(()=>createClient(),[]);
  const[schemeId,setSchemeId]=useState("");
  const[result,setResult]=useState<Result|null>(null);
  const[busy,setBusy]=useState(false);
  const[error,setError]=useState<string|null>(null);

  async function simulate(e:FormEvent<HTMLFormElement>){
    e.preventDefault();setBusy(true);setError(null);setResult(null);
    const fd=new FormData(e.currentTarget);
    const {data,error}=await supabase.rpc("resolve_payer_billing_rule",{
      p_practice_id:practiceId,
      p_practitioner_id:String(fd.get("practitioner_id")||"")||null,
      p_scheme_id:String(fd.get("medical_scheme_id")||"")||null,
      p_option_id:String(fd.get("medical_scheme_option_id")||"")||null,
      p_code_system:String(fd.get("code_system")||"CCSA"),
      p_code:String(fd.get("code")||""),
      p_service_date:String(fd.get("service_date")||today()),
      p_reference_amount:Number(fd.get("reference_amount")||0),
      p_charged_amount:Number(fd.get("charged_amount")||0),
      p_quantity:Number(fd.get("quantity")||1),
    });
    setBusy(false);
    if(error){setError(error.message);return;}
    setResult(data as Result);
  }

  const scopedOptions=options.filter(o=>o.medical_scheme_id===schemeId);
  return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h3 className="font-semibold text-[#4a1f3e]">Rule simulator</h3><p className="mt-1 max-w-3xl text-sm text-stone-500">Test what PracticeCtrl would apply for a provider, scheme, option, code and service date. Simulation is read-only: it does not alter invoices, claims or contract records.</p></div>
      <span className="rounded-full bg-sky-50 px-3 py-1 text-xs font-medium text-sky-800">No data persisted</span>
    </div>
    <form onSubmit={simulate} className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <select name="medical_scheme_id" required value={schemeId} onChange={(e:ChangeEvent<HTMLSelectElement>)=>setSchemeId(e.target.value)} className="rounded-xl border border-stone-300 px-3 py-2 text-sm xl:col-span-2"><option value="">Select medical scheme</option>{schemes.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select>
      <select name="medical_scheme_option_id" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">Scheme level / all options</option>{scopedOptions.map(o=><option key={o.id} value={o.id}>{o.option_name} · {o.benefit_year}</option>)}</select>
      <select name="practitioner_id" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">Practice-wide</option>{practitioners.map(p=><option key={p.id} value={p.id}>{p.display_name}</option>)}</select>
      <input name="code_system" defaultValue="CCSA" placeholder="Code system" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="code" required placeholder="Tariff / procedure code" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <label className="text-xs text-stone-500">Service date<input name="service_date" type="date" required defaultValue={today()} className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2 text-sm text-stone-800"/></label>
      <input name="quantity" type="number" min="0.01" step="0.01" defaultValue="1" placeholder="Quantity" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="reference_amount" type="number" min="0" step="0.01" required placeholder="Reference tariff (R)" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="charged_amount" type="number" min="0" step="0.01" required placeholder="Practice fee (R)" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <button disabled={busy} className="rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50 sm:col-span-2 xl:col-span-2">{busy?"Simulating…":"Run simulation"}</button>
    </form>
    {error?<p role="alert" className="mt-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-800">{error}</p>:null}
    {result?<div className="mt-5 rounded-2xl border border-stone-200 bg-stone-50 p-4">
      <div className="flex flex-wrap items-center justify-between gap-3"><div><p className="text-sm font-semibold text-stone-900">{result.matched?"Contractual tariff rule matched":"No contractual tariff rule matched"}</p><p className="mt-1 text-xs text-stone-500">Precedence: {result.precedence_level?.replaceAll("_"," ")||"reference only"} · confidence {result.confidence}</p></div><span className={`rounded-full px-2.5 py-1 text-xs font-semibold ${result.matched?"bg-emerald-100 text-emerald-800":"bg-amber-100 text-amber-800"}`}>{result.matched?"MATCHED":"REVIEW"}</span></div>
      <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><ResultMetric label="Reference tariff" value={money(result.reference_amount)}/><ResultMetric label="Practice fee" value={money(result.charged_amount)}/><ResultMetric label="Expected scheme" value={money(result.expected_scheme_amount)}/><ResultMetric label="Estimated patient" value={money(result.estimated_patient_liability)}/></div>
      {result.matched?<p className="mt-3 text-xs text-stone-600">Method: {result.calculation_method?.replaceAll("_"," ")||"—"}{result.rate_percent!=null?` · ${result.rate_percent}%`:""}{result.fixed_amount!=null?` · fixed ${money(result.fixed_amount)}`:""}</p>:null}
      {result.requirements?.length?<div className="mt-4"><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Additional applicable rules</p><div className="mt-2 grid gap-2">{result.requirements.map((r,i)=><div key={`${r.rule_id}-${i}`} className="rounded-xl border border-stone-200 bg-white px-3 py-2 text-xs"><span className="font-medium text-stone-800">{r.rule_type.replaceAll("_"," ")}</span><span className="text-stone-500"> · {r.scope.replaceAll("_"," ")}</span><pre className="mt-1 overflow-x-auto whitespace-pre-wrap font-sans text-stone-500">{JSON.stringify(r.requirements&&Object.keys(r.requirements).length?r.requirements:r.rule_value,null,2)}</pre></div>)}</div></div>:null}
      {result.source_document_id?<p className="mt-3 break-all text-[11px] text-stone-400">Evidence source: {result.source_document_id}</p>:null}
    </div>:null}
  </section>;
}

function ResultMetric({label,value}:{label:string;value:string}){return <div className="rounded-xl border border-stone-200 bg-white p-3"><p className="text-[11px] uppercase tracking-wide text-stone-500">{label}</p><p className="mt-1 text-base font-semibold text-[#4a1f3e]">{value}</p></div>}
