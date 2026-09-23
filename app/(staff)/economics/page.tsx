import Link from "next/link";
import { SectionHeader } from "@/components/SectionHeader";
import { PracticeEconomicsDashboard } from "@/components/economics/PracticeEconomicsDashboard";
import { EconomicsInvestigator } from "@/components/economics/EconomicsInvestigator";
import { requireStaffContext } from "@/lib/auth/server";
import { canViewEconomics } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

const WINDOWS=[30,90,365] as const;
function isoDate(d:Date){return d.toISOString().slice(0,10);}

export default async function EconomicsPage({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){
  const staff=await requireStaffContext();
  if(!canViewEconomics(staff.role))return <p className="text-sm text-stone-600">Your role does not have Practice Economics access.</p>;
  const sp=await searchParams;
  const raw=Array.isArray(sp.window)?sp.window[0]:sp.window;
  const requested=Number(raw||30);
  const windowDays=(WINDOWS as readonly number[]).includes(requested)?requested:30;
  const end=new Date(); const start=new Date(end); start.setDate(start.getDate()-windowDays+1);
  const startDate=isoDate(start); const endDate=isoDate(end);
  const supabase=await createClient();
  const [overview,scheme,plan,procedure,waterfall,productivity,aiReadiness]=await Promise.all([
    supabase.rpc("get_practice_economics_overview",{p_practice_id:staff.practiceId,p_start_date:startDate,p_end_date:endDate}),
    supabase.rpc("get_practice_economics_slice",{p_practice_id:staff.practiceId,p_start_date:startDate,p_end_date:endDate,p_dimensions:["scheme"],p_filters:{}}),
    supabase.rpc("get_practice_economics_slice",{p_practice_id:staff.practiceId,p_start_date:startDate,p_end_date:endDate,p_dimensions:["scheme","plan"],p_filters:{}}),
    supabase.rpc("get_practice_economics_slice",{p_practice_id:staff.practiceId,p_start_date:startDate,p_end_date:endDate,p_dimensions:["procedure"],p_filters:{}}),
    supabase.rpc("get_practice_economics_waterfall",{p_practice_id:staff.practiceId,p_start_date:startDate,p_end_date:endDate,p_filters:{}}),
    supabase.rpc("get_practitioner_economics_productivity",{p_practice_id:staff.practiceId,p_start_date:startDate,p_end_date:endDate}),
    supabase.rpc("get_economics_ai_readiness",{p_practice_id:staff.practiceId})
  ]);
  const errors=[overview,scheme,plan,procedure,waterfall,productivity,aiReadiness].map(x=>x.error).filter(Boolean);
  if(errors.length)throw errors[0];
  return <div className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-4">
      <SectionHeader title="Practice Economics" body="RVU/IRU workload, expected reimbursement, realised value, payer/plan economics and revenue leakage. Every metric is derived from claim-line economics and remains drillable to source transactions."/>
      <div className="flex flex-wrap gap-2">{WINDOWS.map(days=><Link key={days} href={`/economics?window=${days}`} className={`rounded-xl border px-3 py-2 text-xs font-medium ${windowDays===days?"border-[#067c80] bg-[#067c80] text-white":"border-[#cfd8e3] bg-white text-[#334155]"}`}>{days===365?"12 months":`${days} days`}</Link>)}</div>
    </div>
    <PracticeEconomicsDashboard overview={(overview.data||{}) as any} scheme={(scheme.data||{}) as any} plan={(plan.data||{}) as any} procedure={(procedure.data||{}) as any} waterfall={(waterfall.data||{}) as any} productivity={(productivity.data||{}) as any}/>
    <EconomicsInvestigator practiceId={staff.practiceId} readiness={(aiReadiness.data||{}) as any}/>
  </div>;
}
