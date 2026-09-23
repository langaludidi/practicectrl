"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { StatusPill } from "@/components/StatusPill";
import { createClient } from "@/lib/supabase/client";

type Membership={
  id:string; scheme_name_snapshot:string; option_name_snapshot:string|null; member_number_masked:string;
  dependant_code:string|null; membership_status:string; effective_from:string|null; effective_to:string|null;
  verification_source:string|null; verified_at:string|null;
};
type VerificationCase={
  id:string; membership_id:string; verification_method:string; status:string; external_reference:string|null;
  evidence_document_id:string|null; effective_from:string|null; effective_to:string|null; notes:string|null;
  requested_at:string; resolved_at:string|null;
};
type EvidenceDocument={id:string;title:string;document_type:string;status:string;created_at:string};

function nice(value:string|null|undefined){return value?value.replaceAll("_"," "):"—"}

export function MembershipVerificationPanel({memberships,cases,documents,returnToIntegrity}:{memberships:Membership[];cases:VerificationCase[];documents:EvidenceDocument[];returnToIntegrity?:boolean}){
  const supabase=useMemo(()=>createClient(),[]);
  const [busy,setBusy]=useState<string|null>(null);
  const [msg,setMsg]=useState<string|null>(null);
  const openCaseByMembership=useMemo(()=>new Map(cases.filter(c=>c.status==="pending").map(c=>[c.membership_id,c])),[cases]);
  const evidence=documents.filter(d=>["generated","signed"].includes(d.status));

  async function openVerification(membershipId:string,formData:FormData){
    const method=String(formData.get("method")||"manual_evidence");
    setBusy(membershipId);setMsg(null);
    const {error}=await supabase.rpc("open_scheme_membership_verification",{p_membership_id:membershipId,p_method:method,p_notes:null});
    setBusy(null);
    if(error)setMsg(error.message);else window.location.reload();
  }

  async function resolveVerification(caseId:string,formData:FormData){
    const outcome=String(formData.get("outcome")||"");
    const evidenceId=String(formData.get("evidenceDocumentId")||"")||null;
    const reference=String(formData.get("externalReference")||"")||null;
    const effectiveFrom=String(formData.get("effectiveFrom")||"")||null;
    const effectiveTo=String(formData.get("effectiveTo")||"")||null;
    const notes=String(formData.get("notes")||"")||null;
    setBusy(caseId);setMsg(null);
    const {error}=await supabase.rpc("resolve_scheme_membership_verification",{
      p_case_id:caseId,p_outcome:outcome,p_external_reference:reference,p_evidence_document_id:evidenceId,
      p_effective_from:effectiveFrom,p_effective_to:effectiveTo,p_notes:notes
    });
    setBusy(null);
    if(error)setMsg(error.message);else window.location.reload();
  }

  return <article id="scheme-membership" className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm scroll-mt-24">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h3 className="font-semibold text-[#4a1f3e]">Medical-scheme memberships</h3><p className="mt-1 text-sm text-stone-500">Patient-supplied membership remains unverified until PracticeCtrl records authoritative evidence or a connected verification response.</p></div>
      {returnToIntegrity?<Link href="/integrity" className="rounded-lg border border-stone-300 px-3 py-1.5 text-xs font-medium hover:bg-stone-50">← Return to Revenue Integrity</Link>:null}
    </div>
    <div className="mt-4 grid gap-4">
      {memberships.map(m=>{const openCase=openCaseByMembership.get(m.id);const recent=cases.filter(c=>c.membership_id===m.id).slice(0,3);return <div key={m.id} className="rounded-xl border border-stone-200 p-4">
        <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-sm font-medium">{m.scheme_name_snapshot}{m.option_name_snapshot?` · ${m.option_name_snapshot}`:""}</p><p className="mt-1 text-xs text-stone-500">Member {m.member_number_masked}{m.dependant_code?` · dependant ${m.dependant_code}`:""}</p>{m.verified_at?<p className="mt-1 text-xs text-stone-500">Verified {new Date(m.verified_at).toLocaleString()} · {nice(m.verification_source)}</p>:null}</div><StatusPill value={m.membership_status}/></div>
        {!openCase?<form action={(fd:FormData)=>openVerification(m.id,fd)} className="mt-4 flex flex-col gap-2 rounded-xl bg-stone-50 p-3 sm:flex-row sm:items-end"><label className="flex-1 text-xs font-medium text-stone-600">Verification route<select name="method" defaultValue="manual_evidence" className="mt-1 w-full rounded-lg border border-stone-300 bg-white px-2.5 py-2 text-xs"><option value="manual_evidence">Verified supporting document</option><option value="scheme_portal">Authoritative scheme portal / call centre</option><option value="other_authoritative">Other authoritative source</option></select></label><button disabled={busy===m.id} className="rounded-lg bg-[#4a1f3e] px-3 py-2 text-xs font-semibold text-white disabled:opacity-50">{busy===m.id?"Opening…":"Start verification"}</button></form>:<form action={(fd:FormData)=>resolveVerification(openCase.id,fd)} className="mt-4 rounded-xl border border-amber-200 bg-amber-50/50 p-3"><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-wide text-amber-800">Verification in progress</p><p className="mt-1 text-xs text-stone-600">Route: {nice(openCase.verification_method)} · opened {new Date(openCase.requested_at).toLocaleString()}</p></div><span className="rounded-full bg-amber-100 px-2 py-1 text-[11px] font-medium text-amber-900">pending</span></div><div className="mt-3 grid gap-2 sm:grid-cols-2"><label className="text-xs text-stone-600">Outcome<select name="outcome" required defaultValue="verified" className="mt-1 w-full rounded-lg border border-stone-300 bg-white px-2.5 py-2 text-xs"><option value="verified">Active / verified</option><option value="inactive">Inactive / verified</option><option value="failed">Verification failed</option><option value="unavailable">Verification unavailable</option><option value="cancelled">Cancel case</option></select></label><label className="text-xs text-stone-600">Authoritative reference<input name="externalReference" placeholder="Portal / call / response reference" className="mt-1 w-full rounded-lg border border-stone-300 bg-white px-2.5 py-2 text-xs"/></label><label className="text-xs text-stone-600 sm:col-span-2">Patient evidence document<select name="evidenceDocumentId" defaultValue="" className="mt-1 w-full rounded-lg border border-stone-300 bg-white px-2.5 py-2 text-xs"><option value="">No evidence document selected</option>{evidence.map(d=><option key={d.id} value={d.id}>{d.title} · {nice(d.document_type)} · {d.status}</option>)}</select></label><label className="text-xs text-stone-600">Effective from<input name="effectiveFrom" type="date" className="mt-1 w-full rounded-lg border border-stone-300 bg-white px-2.5 py-2 text-xs"/></label><label className="text-xs text-stone-600">Effective to<input name="effectiveTo" type="date" className="mt-1 w-full rounded-lg border border-stone-300 bg-white px-2.5 py-2 text-xs"/></label><label className="text-xs text-stone-600 sm:col-span-2">Notes<textarea name="notes" className="mt-1 min-h-16 w-full rounded-lg border border-stone-300 bg-white px-2.5 py-2 text-xs" placeholder="What was checked and by whom?"/></label></div><div className="mt-3 flex flex-wrap items-center justify-between gap-2"><p className="max-w-xl text-[11px] text-stone-500">Manual evidence requires a generated or signed patient document. Portal/authoritative checks require a reference. PracticeCtrl will not mark membership verified without one of those controls.</p><button disabled={busy===openCase.id} className="rounded-lg bg-[#4a1f3e] px-3 py-2 text-xs font-semibold text-white disabled:opacity-50">{busy===openCase.id?"Saving…":"Record verification outcome"}</button></div></form>}
        {recent.length?<div className="mt-3 border-t border-stone-100 pt-3"><p className="text-[11px] font-semibold uppercase tracking-wide text-stone-500">Verification history</p><div className="mt-2 grid gap-1">{recent.map(c=><p key={c.id} className="text-xs text-stone-500">{new Date(c.requested_at).toLocaleDateString()} · {nice(c.verification_method)} · <span className="font-medium text-stone-700">{nice(c.status)}</span>{c.external_reference?` · ref ${c.external_reference}`:""}</p>)}</div></div>:null}
      </div>})}
      {!memberships.length?<p className="text-sm text-stone-500">No scheme membership stored.</p>:null}
    </div>
    <div className="mt-4 rounded-xl bg-sky-50 p-3 text-xs text-sky-900">Until a production switching or scheme API is connected, PracticeCtrl records controlled manual/portal verification evidence. It does not present patient-entered details as real-time scheme verification.</div>
    {msg?<p className="mt-3 rounded-xl bg-stone-100 p-3 text-sm text-stone-700">{msg}</p>:null}
  </article>;
}
