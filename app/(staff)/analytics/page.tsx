import Link from "next/link";
import { CommandCentre } from "@/components/analytics/CommandCentre";
import { SectionHeader } from "@/components/SectionHeader";
import { requireStaffContext } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";

const WINDOWS=[7,30,90,365] as const;

export default async function AnalyticsPage({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){
  const staff=await requireStaffContext();
  const sp=await searchParams;
  const raw=Array.isArray(sp.window)?sp.window[0]:sp.window;
  const requested=Number(raw||30);
  const windowDays=(WINDOWS as readonly number[]).includes(requested)?requested:30;
  const supabase=await createClient();
  const{data,error}=await supabase.rpc("get_practicectrl_command_centre",{p_practice_id:staff.practiceId,p_window_days:windowDays});
  if(error)throw error;
  return <div className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-4"><SectionHeader title="PracticeCtrl Command Centre" body="Operational, clinical-coding and revenue intelligence from one governed practice view. Financial metrics are role-gated in the database as well as the interface."/><div className="flex flex-wrap gap-2">{WINDOWS.map(days=><Link key={days} href={`/analytics?window=${days}`} className={`rounded-xl border px-3 py-2 text-xs font-medium ${windowDays===days?"border-[#4a1f3e] bg-[#4a1f3e] text-white":"border-stone-300 bg-white text-stone-700"}`}>{days===365?"12 months":`${days} days`}</Link>)}</div></div>
    <CommandCentre data={(data||{}) as any}/>
  </div>;
}
