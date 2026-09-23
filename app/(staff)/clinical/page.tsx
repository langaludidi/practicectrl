import { ClinicalWorkspace } from "@/components/clinical/ClinicalWorkspace";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewClinicalRecords, canManageClinicalRecords } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";
import { shortDate, shortDateTime } from "@/lib/format";

export default async function ClinicalPage(){
  const staff=await requireStaffContext();
  if(!canViewClinicalRecords(staff.role)) return <p className="text-sm text-stone-600">Your role does not have access to detailed clinical records.</p>;
  const supabase=await createClient();
  const[{data:patients},{data:encounters},{data:notes},{data:observations}]=await Promise.all([
    supabase.from("crm_patient").select("id,display_name").eq("practice_id",staff.practiceId).eq("status","active").order("display_name").limit(500),
    supabase.from("practice_encounter").select("id,patient_id,service_date,encounter_type,status,practitioner_user_id").eq("practice_id",staff.practiceId).order("service_date",{ascending:false}).limit(100),
    supabase.from("clinical_note").select("id,patient_id,encounter_id,note_type,title,subjective,objective,assessment,plan,narrative,status,signed_at,content_sha256,created_at").eq("practice_id",staff.practiceId).order("created_at",{ascending:false}).limit(100),
    supabase.from("clinical_observation").select("id,patient_id,encounter_id,observation_type,value_numeric,value_text,unit,observed_at").eq("practice_id",staff.practiceId).order("observed_at",{ascending:false}).limit(100),
  ]);
  const patientMap=new Map((patients||[]).map((p:any)=>[p.id,p.display_name]));
  return <div className="space-y-6"><SectionHeader title="Clinical Records" body="Encounter-centred clinical documentation. Signed notes are fingerprinted and retained as immutable clinical evidence; amendments create a linked new draft."/>
    <ClinicalWorkspace practiceId={staff.practiceId} userId={staff.userId} patients={(patients||[]) as any} encounters={(encounters||[]) as any} notes={(notes||[]) as any} canWrite={canManageClinicalRecords(staff.role)} canSign={staff.role==="practitioner"}/>
    <section className="grid gap-4 xl:grid-cols-2"><article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Recent clinical notes</h3><div className="mt-4 grid gap-3">{(notes||[]).map((n:any)=><div key={n.id} className="rounded-xl border border-stone-200 p-3"><div className="flex items-start justify-between gap-3"><div><p className="text-sm font-medium">{n.title||n.note_type}</p><p className="mt-1 text-xs text-stone-500">{patientMap.get(n.patient_id)||"Patient"} · {shortDateTime(n.created_at)}</p></div><StatusPill value={n.status}/></div>{n.assessment?<p className="mt-2 line-clamp-2 text-sm text-stone-600">{n.assessment}</p>:null}{n.content_sha256?<p className="mt-2 truncate font-mono text-[10px] text-stone-400">SHA-256 {n.content_sha256}</p>:null}</div>)}{!(notes||[]).length?<p className="text-sm text-stone-500">No clinical notes yet.</p>:null}</div></article><article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Recent observations</h3><div className="mt-4 grid gap-3">{(observations||[]).map((o:any)=><div key={o.id} className="flex items-center justify-between rounded-xl border border-stone-200 p-3"><div><p className="text-sm font-medium">{o.observation_type}</p><p className="text-xs text-stone-500">{patientMap.get(o.patient_id)||"Patient"} · {shortDateTime(o.observed_at)}</p></div><span className="font-medium">{o.value_numeric??o.value_text} {o.unit||""}</span></div>)}{!(observations||[]).length?<p className="text-sm text-stone-500">No observations recorded.</p>:null}</div></article></section>
  </div>;
}
