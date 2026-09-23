"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function CommunicationDraftForm({practiceId,patients}:{practiceId:string;patients:Array<{id:string;display_name:string}>}){
  const supabase=createClient();
  const[msg,setMsg]=useState<string|null>(null);
  const[busy,setBusy]=useState(false);
  async function submit(fd:FormData){
    setBusy(true);setMsg(null);
    const patientId=String(fd.get("patientId")||"")||null;
    const threadType=String(fd.get("threadType")||"administrative");
    const subject=String(fd.get("subject")||"").trim()||null;
    const body=String(fd.get("body")||"").trim();
    const channel=String(fd.get("channel")||"email");
    const recipient=String(fd.get("recipient")||"").trim()||null;
    const containsClinicalDetail=fd.get("containsClinicalDetail")==="on";
    const{error}=await supabase.rpc("create_communication_draft",{
      p_practice_id:practiceId,p_patient_id:patientId,p_thread_type:threadType,p_channel:channel,
      p_recipient:recipient,p_subject:subject,p_body:body,p_contains_clinical_detail:containsClinicalDetail
    });
    setBusy(false);
    if(error)setMsg(error.message);else{setMsg("Draft created. Nothing was sent.");window.location.reload();}
  }
  return <form action={submit} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <h3 className="font-semibold text-[#4a1f3e]">Create communication draft</h3>
    <p className="mt-1 text-sm text-stone-500">Drafting does not send. The central RPC enforces tenant membership, AAL2 and clinical-detail role boundaries.</p>
    <div className="mt-4 grid gap-3 sm:grid-cols-2">
      <select name="patientId" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">No patient link</option>{patients.map(p=><option key={p.id} value={p.id}>{p.display_name}</option>)}</select>
      <select name="threadType" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="administrative">Administrative</option><option value="appointment">Appointment</option><option value="billing">Billing</option><option value="claim">Claim</option><option value="referral">Referral</option></select>
      <select name="channel" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="email">Email</option><option value="sms">SMS</option><option value="whatsapp">WhatsApp</option><option value="phone">Phone</option></select>
      <input name="recipient" placeholder="Recipient address / number" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
      <input name="subject" placeholder="Subject" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/>
      <textarea name="body" required rows={4} placeholder="Administrative message draft" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/>
      <label className="flex items-center gap-2 text-xs text-stone-600 sm:col-span-2"><input type="checkbox" name="containsClinicalDetail"/>This draft contains clinical detail and must use a health-data-approved route.</label>
    </div>
    <button disabled={busy} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Save draft</button>
    {msg?<p className="mt-3 text-sm text-stone-600">{msg}</p>:null}
  </form>;
}
