"use client";

import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { StatusPill } from "@/components/StatusPill";
import { shortDateTime } from "@/lib/format";

type Metrics = Record<string, number | null | undefined>;
type Readiness = { scheduler_active?: boolean; staging_transport_ready?: boolean; production_transport_ready?: boolean; blockers?: Array<{code:string;scope:string;message:string}>; routes?: Record<string, number>; templates?: Record<string, number>; rules?: Record<string, number>; exceptions?: Record<string, number> };
type Rule = {
  id: string; rule_key: string; name: string; trigger_type: string; purpose: string;
  channel_strategy: string; template_group_key: string; lead_minutes: number; environment: string;
  enabled: boolean; requires_explicit_preference: boolean; quiet_start: string; quiet_end: string;
  approved_at?: string | null;
};
type Template = {
  id: string; template_key: string; name: string; channel: string; purpose: string;
  subject_template?: string | null; body_template: string; active: boolean;
  approved_at?: string | null;
};
type Job = {
  id: string; channel?: string | null; scheduled_for: string; status: string;
  suppression_reason?: string | null; block_reason?: string | null; attempt_count: number; updated_at: string;
};
type Route = { channel: string; environment: string; enabled: boolean; provider_id: string };
type Provider = { id: string; display_name: string; channel: string; status: string; transport_ready: boolean; health_data_approved: boolean };

function n(v: unknown){ return Number(v ?? 0); }
function title(v: string){ return v.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase()); }

export function CommunicationAutomationConsole({practiceId,canManage,metrics,readiness,rules,templates,jobs,routes,providers}:{
  practiceId:string; canManage:boolean; metrics:Metrics; readiness:Readiness; rules:Rule[]; templates:Template[]; jobs:Job[]; routes:Route[]; providers:Provider[];
}){
  const supabase=useMemo(()=>createClient(),[]);
  const[busy,setBusy]=useState<string|null>(null);
  const[msg,setMsg]=useState<string|null>(null);

  async function approveTemplate(id:string){
    setBusy(`tpl:${id}`); setMsg(null);
    const{error}=await supabase.rpc("approve_communication_template",{p_template_id:id,p_active:true});
    setBusy(null);
    if(error){setMsg(error.message);return;} window.location.reload();
  }
  async function toggleRule(id:string,enabled:boolean){
    setBusy(`rule:${id}`); setMsg(null);
    const{error}=await supabase.rpc("set_communication_automation_rule_enabled",{p_rule_id:id,p_enabled:enabled});
    setBusy(null);
    if(error){setMsg(error.message);return;} window.location.reload();
  }
  async function runNow(){
    setBusy("run"); setMsg(null);
    const{data,error}=await supabase.rpc("run_communication_automation_now",{p_practice_id:practiceId});
    setBusy(null);
    if(error){setMsg(error.message);return;}
    setMsg(`Cycle complete: ${JSON.stringify(data)}`); window.location.reload();
  }

  const providerById=new Map(providers.map(p=>[p.id,p]));
  return <section className="space-y-5">
    <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div><h3 className="font-semibold text-[#4a1f3e]">Automation control plane</h3><p className="mt-1 text-sm text-stone-500">Consent-aware scheduling, approved templates, quiet hours, governed routes and delivery failure accountability.</p></div>
        {canManage?<button type="button" disabled={busy!==null} onClick={runNow} className="rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Run controlled cycle</button>:null}
      </div>
      <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
        <Mini label="Enabled rules" value={`${n(metrics.rules_enabled)}/${n(metrics.rules_total)}`}/>
        <Mini label="Approved templates" value={`${n(metrics.templates_approved)}/${n(metrics.templates_total)}`}/>
        <Mini label="Scheduled" value={n(metrics.jobs_scheduled)}/>
        <Mini label="Blocked" value={n(metrics.jobs_blocked)}/>
        <Mini label="Queued" value={n(metrics.messages_queued)}/>
        <Mini label="Failures" value={n(metrics.delivery_failures)}/>
      </div>
      {msg?<p className="mt-4 rounded-xl border border-stone-200 bg-stone-50 p-3 text-xs text-stone-700">{msg}</p>:null}
    </div>


    <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div><h3 className="font-semibold text-[#4a1f3e]">Communications readiness</h3><p className="mt-1 text-sm text-stone-500">Separates safe automation configuration from actual external transport readiness.</p></div>
        <div className="flex gap-2"><StatusPill value={readiness.scheduler_active?"scheduler active":"scheduler inactive"}/><StatusPill value={readiness.staging_transport_ready?"staging ready":"staging blocked"}/><StatusPill value={readiness.production_transport_ready?"production ready":"production blocked"}/></div>
      </div>
      {(readiness.blockers||[]).length?<div className="mt-4 grid gap-2">{(readiness.blockers||[]).map(b=><div key={`${b.code}-${b.scope}`} className="rounded-xl border border-amber-200 bg-amber-50 p-3"><p className="text-xs font-semibold text-amber-900">{b.code} · {b.scope}</p><p className="mt-1 text-xs text-amber-800">{b.message}</p></div>)}</div>:<p className="mt-4 text-sm text-emerald-700">No communications-readiness blockers are recorded.</p>}
    </div>
    <div className="grid gap-4 xl:grid-cols-2">
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <h3 className="font-semibold text-[#4a1f3e]">Automation rules</h3>
        <p className="mt-1 text-xs text-stone-500">Rules cannot be enabled until a manager or system administrator approves them at AAL2.</p>
        <div className="mt-4 grid gap-3">{rules.map(rule=><div key={rule.id} className="rounded-xl border border-stone-200 p-4">
          <div className="flex items-start justify-between gap-3"><div><p className="text-sm font-medium">{rule.name}</p><p className="mt-1 text-xs text-stone-500">{title(rule.trigger_type)} · {title(rule.channel_strategy)} · {rule.environment}</p></div><StatusPill value={rule.enabled?"enabled":"disabled"}/></div>
          <p className="mt-2 text-xs text-stone-500">Lead {Math.round(rule.lead_minutes/60)}h · quiet {rule.quiet_start.slice(0,5)}–{rule.quiet_end.slice(0,5)} · explicit preference {rule.requires_explicit_preference?"required":"not required"}</p>
          {canManage?<button type="button" disabled={busy!==null} onClick={()=>toggleRule(rule.id,!rule.enabled)} className="mt-3 rounded-lg border border-stone-300 px-3 py-1.5 text-xs font-medium disabled:opacity-50">{rule.enabled?"Disable":"Approve & enable"}</button>:null}
        </div>)}{!rules.length?<p className="text-sm text-stone-500">No automation rules configured.</p>:null}</div>
      </article>

      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <h3 className="font-semibold text-[#4a1f3e]">Approved message templates</h3>
        <p className="mt-1 text-xs text-stone-500">Automation only materializes templates that have been explicitly approved.</p>
        <div className="mt-4 grid gap-3">{templates.map(t=><div key={t.id} className="rounded-xl border border-stone-200 p-4">
          <div className="flex items-start justify-between gap-3"><div><p className="text-sm font-medium">{t.name}</p><p className="mt-1 text-xs text-stone-500">{t.channel.toUpperCase()} · {t.template_key}</p></div><StatusPill value={t.approved_at?"approved":"pending"}/></div>
          {t.subject_template?<p className="mt-3 text-xs font-medium text-stone-700">{t.subject_template}</p>:null}
          <p className="mt-2 text-xs leading-5 text-stone-600">{t.body_template}</p>
          {canManage&&!t.approved_at?<button type="button" disabled={busy!==null} onClick={()=>approveTemplate(t.id)} className="mt-3 rounded-lg border border-stone-300 px-3 py-1.5 text-xs font-medium disabled:opacity-50">Approve template</button>:null}
        </div>)}{!templates.length?<p className="text-sm text-stone-500">No templates configured.</p>:null}</div>
      </article>
    </div>

    <div className="grid gap-4 xl:grid-cols-2">
      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <h3 className="font-semibold text-[#4a1f3e]">Provider routes</h3><p className="mt-1 text-xs text-stone-500">A message cannot be queued externally without an enabled, approved and transport-ready route.</p>
        <div className="mt-4 grid gap-3">{routes.map((r,i)=>{const p=providerById.get(r.provider_id);return <div key={`${r.channel}-${r.environment}-${i}`} className="rounded-xl border border-stone-200 p-3"><div className="flex items-center justify-between gap-2"><p className="text-sm font-medium">{r.channel.toUpperCase()} · {r.environment}</p><StatusPill value={r.enabled?"enabled":"disabled"}/></div><p className="mt-1 text-xs text-stone-500">{p?.display_name||"Unknown provider"} · {p?.status||"unregistered"} · transport {p?.transport_ready?"ready":"not ready"}</p></div>})}{!routes.length?<p className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">No email, SMS or WhatsApp delivery route is configured. Automation can schedule and govern messages, but external dispatch remains blocked.</p>:null}</div>
      </article>

      <article className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
        <h3 className="font-semibold text-[#4a1f3e]">Recent automation jobs</h3><p className="mt-1 text-xs text-stone-500">Suppressed and blocked jobs remain auditable without sending.</p>
        <div className="mt-4 grid gap-3">{jobs.map(j=><div key={j.id} className="rounded-xl border border-stone-200 p-3"><div className="flex items-start justify-between gap-3"><div><p className="text-sm font-medium">{j.channel?.toUpperCase()||"Channel pending"}</p><p className="mt-1 text-xs text-stone-500">Scheduled {shortDateTime(j.scheduled_for)} · attempts {j.attempt_count}</p></div><StatusPill value={j.status}/></div>{j.suppression_reason?<p className="mt-2 text-xs text-amber-800">Suppressed: {j.suppression_reason}</p>:null}{j.block_reason?<p className="mt-2 text-xs text-rose-700">Blocked: {j.block_reason}</p>:null}</div>)}{!jobs.length?<p className="text-sm text-stone-500">No automation jobs yet. This is expected while the default rule remains disabled.</p>:null}</div>
      </article>
    </div>
  </section>;
}

function Mini({label,value}:{label:string;value:string|number}){return <div className="rounded-xl border border-stone-200 bg-stone-50 p-3"><p className="text-xs text-stone-500">{label}</p><p className="mt-1 text-xl font-semibold text-stone-900">{value}</p></div>}
