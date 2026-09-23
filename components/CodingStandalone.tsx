"use client";
import { type ChangeEvent, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { ClinicalCodingWorkspace } from "@/src/features/clinical-coding/components/ClinicalCodingWorkspace";

export function CodingStandalone({ practiceId, clinicianCanConfirm }: { practiceId: string; clinicianCanConfirm: boolean }) {
  const supabase = useMemo(() => createClient(), []);
  const [serviceDate, setServiceDate] = useState(() => new Date().toISOString().slice(0,10));
  const [sex, setSex] = useState<"M"|"F"|"U">("U");
  if (!clinicianCanConfirm) return <div className="rounded-2xl border border-amber-200 bg-amber-50 p-5 text-sm text-amber-900">Your role may inspect coding reference information, but final code confirmation is restricted to a practitioner.</div>;
  return <div className="space-y-4"><div className="grid gap-3 rounded-2xl border border-stone-200 bg-white p-4 md:grid-cols-2"><label className="text-sm font-medium">Service date<input type="date" value={serviceDate} onChange={(e: ChangeEvent<HTMLInputElement>)=>setServiceDate(e.target.value)} className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2"/></label><label className="text-sm font-medium">Patient sex (for code validation)<select value={sex} onChange={(e: ChangeEvent<HTMLSelectElement>)=>setSex(e.target.value as "M"|"F"|"U")} className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2"><option value="U">Not specified</option><option value="F">Female</option><option value="M">Male</option></select></label></div><ClinicalCodingWorkspace supabase={supabase} practiceId={practiceId} serviceDate={serviceDate} patientSex={sex}/></div>;
}
