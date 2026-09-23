import Link from "next/link";
import { SectionHeader } from "@/components/SectionHeader";
import { RecoveryOrchestrationWorkspace } from "@/components/revenue/RecoveryOrchestrationWorkspace";
import { requireStaffContext } from "@/lib/auth/server";
import { canManageRecovery, canViewRecovery } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export default async function RecoveryPage({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){
  const staff=await requireStaffContext();
  if(!canViewRecovery(staff.role))return <p className="text-sm text-stone-600">Your role does not have Revenue Recovery access.</p>;
  const sp=await searchParams; const raw=Array.isArray(sp.status)?sp.status[0]:sp.status;
  const status=raw&&["open","closed","all"].includes(raw)?raw:"open";
  const supabase=await createClient();
  const{data,error}=await supabase.rpc("get_revenue_recovery_dashboard",{p_practice_id:staff.practiceId,p_status:status,p_limit:150});
  if(error)throw error;
  return <div className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-4"><SectionHeader title="Recovery Workbench" body="Governed follow-through for recoverable leakage, rejected claims, patient liability, underpayment and recovery deadlines. Financial closure requires an explicit recovery outcome."/><div className="flex flex-wrap gap-2"><Link href="/economics" className="rounded-xl border border-stone-300 bg-white px-3 py-2 text-xs font-medium">Practice Economics</Link>{["open","closed","all"].map(x=><Link key={x} href={`/recovery?status=${x}`} className={`rounded-xl border px-3 py-2 text-xs font-medium ${status===x?"border-[#4a1f3e] bg-[#4a1f3e] text-white":"border-stone-300 bg-white text-stone-700"}`}>{x[0].toUpperCase()+x.slice(1)}</Link>)}</div></div>
    <RecoveryOrchestrationWorkspace practiceId={staff.practiceId} role={staff.role} canManage={canManageRecovery(staff.role)} data={(data||{}) as any}/>
  </div>;
}
