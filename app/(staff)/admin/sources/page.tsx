import Link from "next/link";
import { redirect } from "next/navigation";
import { SectionHeader } from "@/components/SectionHeader";
import { StatusPill } from "@/components/StatusPill";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { shortDateTime } from "@/lib/format";

export default async function SourceRegisterPage(){
  const staff=await requireStaffContext(); if(staff.role!=="system_admin")redirect("/dashboard");
  const supabase=await createClient();
  const [{data:datasets,error:dErr},{data:releases,error:rErr}]=await Promise.all([
    supabase.from("source_dataset").select("id,dataset_key,name,domain,authority_level,access_model,licence_required,versioned_required,provenance_required,effective_dating_required,status,update_frequency").order("domain").order("name"),
    supabase.from("source_dataset_release").select("id,dataset_id,release_name,version,published_date,effective_from,effective_to,retrieved_at,content_sha256,licence_reference,status,source_file_id,activated_at,created_at").order("created_at",{ascending:false}).limit(100),
  ]);
  for(const e of [dErr,rErr])if(e)throw e;
  return <div className="space-y-6">
    <SectionHeader title="Source Register" body="Tenant view of the platform-wide coding, billing, payer and regulatory source state. Raw files and global activation are controlled by the PracticeCtrl platform boundary."/>
    {staff.platformRole?<div className="rounded-2xl border border-[#d9c4d2] bg-[#fbf7fa] p-4 text-sm text-[#4a1f3e]">You also hold a platform role. <Link href="/platform/sources" className="font-semibold underline underline-offset-4">Open global source controls</Link>.</div>:null}
    <section className="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-sm"><div className="border-b border-stone-100 px-5 py-4"><h3 className="font-semibold text-[#4a1f3e]">Datasets & releases</h3></div><div className="overflow-x-auto"><table className="w-full min-w-[1050px] text-left text-sm"><thead className="bg-stone-50 text-xs uppercase tracking-wide text-stone-500"><tr><th className="px-4 py-3">Dataset</th><th className="px-4 py-3">Governance</th><th className="px-4 py-3">Release</th><th className="px-4 py-3">Evidence</th><th className="px-4 py-3">Status</th></tr></thead><tbody>{(datasets||[]).map((d:any)=>{const rs=(releases||[]).filter((r:any)=>r.dataset_id===d.id);return <tr key={d.id} className="border-t border-stone-100 align-top"><td className="px-4 py-3"><p className="font-medium text-stone-800">{d.name}</p><p className="mt-1 text-xs text-stone-500">{d.domain} · {d.authority_level} · {d.access_model}</p></td><td className="px-4 py-3 text-xs text-stone-600"><p>{d.licence_required?"Licence required":"Public/non-licensed"}</p><p>Version {d.versioned_required?"required":"optional"} · provenance {d.provenance_required?"required":"optional"}</p></td><td className="px-4 py-3">{rs.length?rs.map((r:any)=><div key={r.id} className="mb-2 last:mb-0"><p className="text-sm font-medium">{r.release_name}{r.version?` · ${r.version}`:""}</p><p className="text-xs text-stone-500">created {shortDateTime(r.created_at)}</p></div>):<span className="text-xs text-stone-500">No release registered</span>}</td><td className="px-4 py-3">{rs.length?rs.map((r:any)=><div key={r.id} className="mb-2 text-xs text-stone-600 last:mb-0"><p>{r.licence_reference?"Licence evidence recorded":(d.licence_required?"Licence missing":"No licence required")}</p><p className="max-w-[260px] break-all font-mono">{r.content_sha256||"No source hash linked"}</p></div>):"—"}</td><td className="px-4 py-3"><StatusPill value={d.status}/>{rs.map((r:any)=><div key={r.id} className="mt-2"><StatusPill value={r.status}/></div>)}</td></tr>})}</tbody></table></div></section>
  </div>;
}
