import { TenantProvisionPanel } from "@/components/platform/TenantProvisionPanel";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { createClient } from "@/lib/supabase/server";
import { shortDateTime } from "@/lib/format";

export default async function PlatformTenantsPage(){
  const supabase=await createClient();
  const[{data:practices,error:pErr},{data:events,error:eErr}]=await Promise.all([
    supabase.from("practice").select("id,name,tenant_slug,legal_name,country_code,timezone,active,created_at").order("created_at",{ascending:false}),
    supabase.from("platform_tenant_event").select("id,practice_id,event_type,metadata,created_at").order("created_at",{ascending:false}).limit(30),
  ]);
  if(pErr)throw pErr;if(eErr)throw eErr;
  const byPractice=new Map((practices||[]).map((p:any)=>[p.id,p]));
  return <div className="space-y-6"><SectionHeader title="Practice tenants" body="Platform-level tenant registry. Each practice has independent staff memberships, roles, workflow data, integrations and configuration."/><TenantProvisionPanel/><section className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm"><div className="border-b border-stone-100 px-5 py-4"><h3 className="font-semibold text-[#4a1f3e]">Tenant registry</h3></div><div className="overflow-x-auto"><table className="w-full min-w-[850px] text-left text-sm"><thead className="bg-stone-50 text-xs uppercase tracking-wide text-stone-500"><tr><th className="px-4 py-3">Practice</th><th className="px-4 py-3">Tenant key</th><th className="px-4 py-3">Localisation</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Created</th></tr></thead><tbody>{(practices||[]).map((p:any)=><tr key={p.id} className="border-t border-stone-100"><td className="px-4 py-3"><p className="font-medium">{p.name}</p><p className="text-xs text-stone-500">{p.legal_name||"No separate legal name"}</p></td><td className="px-4 py-3 font-mono text-xs">{p.tenant_slug}</td><td className="px-4 py-3 text-xs text-stone-600">{p.country_code} · {p.timezone}</td><td className="px-4 py-3"><StatusPill value={p.active?"active":"inactive"}/></td><td className="px-4 py-3 text-xs text-stone-600">{shortDateTime(p.created_at)}</td></tr>)}</tbody></table></div></section><section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Recent tenant events</h3><div className="mt-4 grid gap-2">{(events||[]).map((e:any)=><div key={e.id} className="flex flex-wrap items-center justify-between gap-2 border-b border-stone-100 py-2 text-sm"><span>{(byPractice.get(e.practice_id) as any)?.name||e.practice_id||"Platform"} · {e.event_type}</span><span className="text-xs text-stone-500">{shortDateTime(e.created_at)}</span></div>)}{!(events||[]).length?<p className="text-sm text-stone-500">No platform tenant events yet.</p>:null}</div></section></div>
}
