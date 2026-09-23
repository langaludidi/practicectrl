"use client";

import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type SummaryPref = {
  preferred_channel?: string | null;
  appointment_reminders?: boolean;
  account_notifications?: boolean;
  clinical_notifications?: boolean;
  results_notifications?: boolean;
  marketing_messages?: boolean;
} | null;

type ExplicitPref = { channel:string; purpose:string; status:string };

const CHANNELS=["email","sms","whatsapp"] as const;
const STATUSES=["unknown","allowed","restricted","withdrawn"] as const;

export function PatientCommunicationPreferences({practiceId,patientId,canEdit,summaryPreference,explicitPreferences}:{
  practiceId:string; patientId:string; canEdit:boolean; summaryPreference:SummaryPref; explicitPreferences:ExplicitPref[];
}){
  const supabase=useMemo(()=>createClient(),[]);
  const[busy,setBusy]=useState<string|null>(null);
  const[msg,setMsg]=useState<string|null>(null);
  const explicitMap=new Map(explicitPreferences.filter(x=>x.purpose==="appointment").map(x=>[x.channel,x.status]));

  async function saveSummary(fd:FormData){
    setBusy("summary");setMsg(null);
    const preferred=String(fd.get("preferred_channel")||"")||null;
    const{error}=await supabase.rpc("set_patient_communication_preferences",{
      p_practice_id:practiceId,
      p_patient_id:patientId,
      p_preferred_channel:preferred,
      p_appointment_reminders:fd.get("appointment_reminders")==="on",
      p_account_notifications:fd.get("account_notifications")==="on",
      p_clinical_notifications:fd.get("clinical_notifications")==="on",
      p_results_notifications:fd.get("results_notifications")==="on",
      p_marketing_messages:fd.get("marketing_messages")==="on"
    });
    setBusy(null);
    if(error){setMsg(error.message);return;} window.location.reload();
  }

  async function saveExplicit(channel:string,status:string){
    setBusy(`explicit:${channel}`);setMsg(null);
    const{error}=await supabase.rpc("record_communication_preference",{
      p_practice_id:practiceId,p_patient_id:patientId,p_channel:channel,p_purpose:"appointment",p_status:status,p_source:"staff"
    });
    setBusy(null);
    if(error){setMsg(error.message);return;} window.location.reload();
  }

  return <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <h3 className="font-semibold text-[#4a1f3e]">Communication preferences</h3>
    <p className="mt-1 text-xs leading-5 text-stone-500">Summary settings control broad communication categories. Automated appointment reminders additionally require an explicit channel-and-purpose status of <strong>allowed</strong>.</p>
    <form action={saveSummary} className="mt-4 grid gap-3">
      <label className="grid gap-1 text-xs text-stone-600">Preferred channel<select name="preferred_channel" defaultValue={summaryPreference?.preferred_channel||""} disabled={!canEdit||busy!==null} className="rounded-xl border border-stone-300 px-3 py-2 text-sm text-stone-900"><option value="">Not recorded</option><option value="email">Email</option><option value="sms">SMS</option><option value="whatsapp">WhatsApp</option><option value="phone">Phone</option></select></label>
      <div className="grid gap-2 sm:grid-cols-2">
        <Check name="appointment_reminders" label="Appointment reminders" defaultChecked={summaryPreference?.appointment_reminders??true} disabled={!canEdit||busy!==null}/>
        <Check name="account_notifications" label="Account notifications" defaultChecked={summaryPreference?.account_notifications??true} disabled={!canEdit||busy!==null}/>
        <Check name="clinical_notifications" label="Clinical notifications" defaultChecked={summaryPreference?.clinical_notifications??true} disabled={!canEdit||busy!==null}/>
        <Check name="results_notifications" label="Results notifications" defaultChecked={summaryPreference?.results_notifications??true} disabled={!canEdit||busy!==null}/>
        <Check name="marketing_messages" label="Marketing messages" defaultChecked={summaryPreference?.marketing_messages??false} disabled={!canEdit||busy!==null}/>
      </div>
      {canEdit?<button disabled={busy!==null} className="w-fit rounded-xl bg-[#4a1f3e] px-4 py-2 text-xs font-medium text-white disabled:opacity-50">Save communication settings</button>:null}
    </form>

    <div className="mt-5 border-t border-stone-200 pt-4">
      <p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Explicit appointment-reminder permission</p>
      <div className="mt-3 grid gap-3">{CHANNELS.map(channel=><div key={channel} className="grid gap-2 rounded-xl border border-stone-200 p-3 sm:grid-cols-[120px_1fr] sm:items-center"><p className="text-sm font-medium uppercase">{channel}</p><select value={explicitMap.get(channel)||"unknown"} disabled={!canEdit||busy!==null} onChange={(e: React.ChangeEvent<HTMLSelectElement>)=>saveExplicit(channel,e.target.value)} className="rounded-lg border border-stone-300 px-3 py-2 text-sm">{STATUSES.map(s=><option key={s} value={s}>{s}</option>)}</select></div>)}</div>
    </div>
    {msg?<p className="mt-3 rounded-xl bg-stone-50 p-3 text-xs text-stone-700">{msg}</p>:null}
  </article>;
}

function Check({name,label,defaultChecked,disabled}:{name:string;label:string;defaultChecked:boolean;disabled:boolean}){return <label className="flex items-center gap-2 rounded-xl border border-stone-200 p-3 text-xs text-stone-700"><input type="checkbox" name={name} defaultChecked={defaultChecked} disabled={disabled}/>{label}</label>}
