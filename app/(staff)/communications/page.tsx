import { CommunicationAutomationConsole } from "@/components/communications/CommunicationAutomationConsole";
import { CommunicationDraftForm } from "@/components/communications/CommunicationDraftForm";
import { CommunicationDispatchActions } from "@/components/communications/CommunicationDispatchActions";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { shortDateTime } from "@/lib/format";

export default async function CommunicationsPage(){
  const staff=await requireStaffContext();
  const supabase=await createClient();
  const canManage=["practice_manager","system_admin"].includes(staff.role);
  const[
    {data:threads},{data:messages},{data:patients},{data:metrics},{data:readiness},
    {data:rules},{data:templates},{data:jobs},{data:routes},{data:providers}
  ]=await Promise.all([
    supabase.from("communication_thread").select("id,patient_id,thread_type,subject,status,owner_user_id,last_activity_at,created_at").eq("practice_id",staff.practiceId).order("last_activity_at",{ascending:false}).limit(100),
    supabase.from("communication_message").select("id,thread_id,direction,channel,status,recipient,subject,contains_clinical_detail,created_at,sent_at").order("created_at",{ascending:false}).limit(250),
    supabase.from("crm_patient").select("id,display_name").eq("practice_id",staff.practiceId).eq("status","active").order("display_name").limit(500),
    supabase.rpc("get_communication_automation_metrics",{p_practice_id:staff.practiceId,p_window_days:30}),
    supabase.rpc("get_communication_readiness",{p_practice_id:staff.practiceId}),
    supabase.from("communication_automation_rule").select("id,rule_key,name,trigger_type,purpose,channel_strategy,template_group_key,lead_minutes,environment,enabled,requires_explicit_preference,quiet_start,quiet_end,approved_at").eq("practice_id",staff.practiceId).order("created_at"),
    supabase.from("communication_template").select("id,template_key,name,channel,purpose,subject_template,body_template,active,approved_at").eq("practice_id",staff.practiceId).order("template_key"),
    supabase.from("communication_automation_job").select("id,channel,scheduled_for,status,suppression_reason,block_reason,attempt_count,updated_at").eq("practice_id",staff.practiceId).order("updated_at",{ascending:false}).limit(50),
    supabase.from("practice_communication_route").select("channel,environment,enabled,provider_id").eq("practice_id",staff.practiceId).order("channel"),
    supabase.from("communication_delivery_provider").select("id,display_name,channel,status,transport_ready,health_data_approved").order("channel")
  ]);

  return <div className="space-y-6">
    <SectionHeader title="Communications" body="Consent-aware communication operations with governed templates, automation scheduling, provider routes, delivery status and failed-delivery accountability."/>
    <CommunicationAutomationConsole
      practiceId={staff.practiceId}
      canManage={canManage}
      metrics={(metrics||{}) as any}
      readiness={(readiness||{}) as any}
      rules={(rules||[]) as any}
      templates={(templates||[]) as any}
      jobs={(jobs||[]) as any}
      routes={(routes||[]) as any}
      providers={(providers||[]) as any}
    />
    <CommunicationDraftForm practiceId={staff.practiceId} patients={(patients||[]) as any}/>
    <section>
      <div className="mb-3"><h3 className="font-semibold text-[#4a1f3e]">Communication history</h3><p className="mt-1 text-sm text-stone-500">Manual and automated messages remain visible in one governed thread history.</p></div>
      <div className="grid gap-4 xl:grid-cols-2">{(threads||[]).map((t:any)=><article key={t.id} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <div className="flex items-start justify-between gap-3"><div><p className="text-sm font-semibold text-[#4a1f3e]">{t.subject||t.thread_type}</p><p className="mt-1 text-xs text-stone-500">{t.thread_type} · last activity {shortDateTime(t.last_activity_at)}</p></div><StatusPill value={t.status}/></div>
        <div className="mt-4 grid gap-2">{(messages||[]).filter((m:any)=>m.thread_id===t.id).slice(0,5).map((m:any)=><div key={m.id} className="rounded-xl border border-stone-200 p-3">
          <div className="flex items-center justify-between gap-2"><p className="text-xs font-medium uppercase tracking-wide text-stone-500">{m.direction} · {m.channel}</p><StatusPill value={m.status}/></div>
          <p className="mt-1 text-xs text-stone-500">{m.recipient||"Internal"} · {shortDateTime(m.sent_at||m.created_at)}{m.contains_clinical_detail?" · clinical detail flagged":""}</p>
          <CommunicationDispatchActions messageId={m.id} status={m.status}/>
        </div>)}</div>
      </article>)}{!(threads||[]).length?<p className="text-sm text-stone-500">No communication threads yet.</p>:null}</div>
    </section>
  </div>;
}
