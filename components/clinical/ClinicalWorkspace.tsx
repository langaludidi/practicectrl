"use client";

import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Patient = { id:string; display_name:string };
type Encounter = { id:string; patient_id:string; service_date:string; encounter_type:string; status:string };
type Note = { id:string; encounter_id:string; note_type:string; title:string|null; subjective:string|null; objective:string|null; assessment:string|null; plan:string|null; narrative:string|null; status:string; signed_at:string|null };

export function ClinicalWorkspace({practiceId,userId,patients,encounters,notes,canWrite,canSign}:{
  practiceId:string; userId:string; patients:Patient[]; encounters:Encounter[]; notes:Note[]; canWrite:boolean; canSign:boolean;
}){
  const supabase=useMemo(()=>createClient(),[]);
  const[busy,setBusy]=useState(false); const[msg,setMsg]=useState<string|null>(null);
  const[draftId,setDraftId]=useState("");
  const selected=notes.find(n=>n.id===draftId);

  async function startEncounter(fd:FormData){setBusy(true);setMsg(null);const{data,error}=await supabase.rpc("create_practice_encounter",{
    p_practice_id:practiceId,p_patient_id:String(fd.get("patientId")),p_service_date:String(fd.get("serviceDate")),p_encounter_type:String(fd.get("encounterType")||"consultation"),p_external_pms_ref:String(fd.get("pmsRef")||"")||null,
  });setBusy(false);if(error)setMsg(error.message);else{setMsg(`Encounter created: ${data}`);window.location.reload();}}

  async function saveNote(fd:FormData){setBusy(true);setMsg(null);const noteId=String(fd.get("noteId")||"")||null;const{data,error}=await supabase.rpc("save_clinical_note",{
    p_note_id:noteId,p_encounter_id:String(fd.get("encounterId")),p_note_type:String(fd.get("noteType")||"consultation"),p_title:String(fd.get("title")||""),p_subjective:String(fd.get("subjective")||""),p_objective:String(fd.get("objective")||""),p_assessment:String(fd.get("assessment")||""),p_plan:String(fd.get("plan")||""),p_narrative:String(fd.get("narrative")||""),
  });setBusy(false);if(error)setMsg(error.message);else{setMsg(`Clinical note saved: ${data}`);window.location.reload();}}

  async function signNote(id:string){setBusy(true);setMsg(null);const{error}=await supabase.rpc("sign_clinical_note",{p_note_id:id});setBusy(false);if(error)setMsg(error.message);else window.location.reload();}
  async function amendNote(id:string){setBusy(true);setMsg(null);const{data,error}=await supabase.rpc("create_clinical_note_amendment",{p_note_id:id});setBusy(false);if(error)setMsg(error.message);else{setMsg(`Amendment draft created: ${data}`);window.location.reload();}}
  async function addObservation(fd:FormData){setBusy(true);setMsg(null);const encounterId=String(fd.get("encounterId"));const encounter=encounters.find(e=>e.id===encounterId);if(!encounter){setBusy(false);setMsg("Select an encounter.");return;}const raw=String(fd.get("value")||"").trim();const numeric=raw!==""&&!Number.isNaN(Number(raw))?Number(raw):null;const{error}=await supabase.from("clinical_observation").insert({practice_id:practiceId,patient_id:encounter.patient_id,encounter_id:encounterId,observation_type:String(fd.get("type")||"").trim(),value_numeric:numeric,value_text:numeric===null?raw:null,unit:String(fd.get("unit")||"").trim()||null,recorded_by:userId});setBusy(false);if(error)setMsg(error.message);else window.location.reload();}

  if(!canWrite) return <div className="rounded-2xl border border-stone-200 bg-white p-5 text-sm text-stone-600">Clinical records are read-only for your current role.</div>;
  return <div className="grid gap-4 xl:grid-cols-2">
    <form action={startEncounter} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#4a1f3e]">Start encounter</h3><p className="mt-1 text-sm text-stone-500">The encounter remains the common anchor for documentation, Code10, billing and claims.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2"><select name="patientId" required className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">Patient</option>{patients.map(p=><option key={p.id} value={p.id}>{p.display_name}</option>)}</select><input name="serviceDate" type="date" required defaultValue={new Date().toISOString().slice(0,10)} className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/><select name="encounterType" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option>consultation</option><option>follow_up</option><option>procedure</option><option>telephone</option></select><input name="pmsRef" placeholder="PMS reference (optional)" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/></div>
      <button disabled={busy} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Start encounter</button>
    </form>

    <form action={addObservation} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#4a1f3e]">Record observation / vital</h3><div className="mt-4 grid gap-3 sm:grid-cols-2"><select name="encounterId" required className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">Encounter</option>{encounters.map(e=><option key={e.id} value={e.id}>{e.service_date} · {patients.find(p=>p.id===e.patient_id)?.display_name||e.patient_id.slice(0,8)}</option>)}</select><input name="type" required placeholder="BP systolic / weight / pulse…" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/><input name="value" required placeholder="Value" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/><input name="unit" placeholder="Unit" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/></div><button disabled={busy} className="mt-4 rounded-xl border border-stone-300 px-4 py-2 text-sm font-medium">Record observation</button>
    </form>

    <form action={saveNote} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm xl:col-span-2">
      <div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="font-semibold text-[#4a1f3e]">Clinical note</h3><p className="mt-1 text-sm text-stone-500">Save drafts freely. Signing creates a SHA-256 content fingerprint and locks the signed record.</p></div><select value={draftId} onChange={(e:any)=>setDraftId(e.target.value)} className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">New note</option>{notes.filter(n=>n.status==="draft").map(n=><option key={n.id} value={n.id}>Edit: {n.title||n.note_type}</option>)}</select></div>
      <input type="hidden" name="noteId" value={draftId}/><div className="mt-4 grid gap-3 sm:grid-cols-2"><select name="encounterId" required defaultValue={selected?.encounter_id||""} key={selected?.encounter_id||"new"} className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">Encounter</option>{encounters.map(e=><option key={e.id} value={e.id}>{e.service_date} · {patients.find(p=>p.id===e.patient_id)?.display_name||e.patient_id.slice(0,8)}</option>)}</select><select name="noteType" defaultValue={selected?.note_type||"consultation"} key={selected?.note_type||"type"} className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option>consultation</option><option>progress</option><option>procedure</option><option>telephone</option><option>review</option><option>other</option></select><input name="title" defaultValue={selected?.title||""} key={(selected?.id||"new")+"title"} placeholder="Clinical note title" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/><textarea name="subjective" defaultValue={selected?.subjective||""} key={(selected?.id||"new")+"s"} placeholder="Subjective / history" className="min-h-24 rounded-xl border border-stone-300 px-3 py-2 text-sm"/><textarea name="objective" defaultValue={selected?.objective||""} key={(selected?.id||"new")+"o"} placeholder="Objective / examination" className="min-h-24 rounded-xl border border-stone-300 px-3 py-2 text-sm"/><textarea name="assessment" defaultValue={selected?.assessment||""} key={(selected?.id||"new")+"a"} placeholder="Assessment / diagnosis" className="min-h-24 rounded-xl border border-stone-300 px-3 py-2 text-sm"/><textarea name="plan" defaultValue={selected?.plan||""} key={(selected?.id||"new")+"p"} placeholder="Plan / treatment / follow-up" className="min-h-24 rounded-xl border border-stone-300 px-3 py-2 text-sm"/><textarea name="narrative" defaultValue={selected?.narrative||""} key={(selected?.id||"new")+"n"} placeholder="Additional clinical narrative" className="min-h-24 rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/></div><button disabled={busy} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Save draft</button>
    </form>

    <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm xl:col-span-2"><h3 className="font-semibold text-[#4a1f3e]">Record actions</h3><div className="mt-4 flex flex-wrap gap-2">{notes.slice(0,20).map(n=><div key={n.id} className="flex items-center gap-2 rounded-xl border border-stone-200 p-2 text-sm"><span>{n.title||n.note_type} · {n.status}</span>{n.status==="draft"&&canSign?<button disabled={busy} onClick={()=>signNote(n.id)} className="rounded-lg bg-[#4a1f3e] px-2.5 py-1 text-xs text-white">Sign</button>:null}{n.status==="signed"&&canSign?<button disabled={busy} onClick={()=>amendNote(n.id)} className="rounded-lg border border-stone-300 px-2.5 py-1 text-xs">Amend</button>:null}</div>)}</div>{msg?<p className="mt-4 rounded-xl bg-stone-50 p-3 text-sm text-stone-700">{msg}</p>:null}</div>
  </div>;
}
