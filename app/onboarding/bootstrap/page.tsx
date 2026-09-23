import { BootstrapAdminForm } from "@/components/onboarding/BootstrapAdminForm";
export default async function BootstrapPage({ searchParams }: { searchParams: Promise<{ tenant?: string }> }){
  const params=await searchParams;
  const tenantSlug=String(params.tenant||"").trim();
  return <main className="mx-auto flex min-h-screen max-w-lg items-center px-5 py-12"><section className="w-full rounded-3xl border border-stone-200 bg-white p-7 shadow-sm"><p className="text-xs font-bold uppercase tracking-[.2em] text-[#b84f45]">PracticeCtrl</p><h1 className="mt-2 text-2xl font-semibold text-[#4a1f3e]">First administrator</h1><p className="mt-2 text-sm text-stone-600">Controlled one-time onboarding for a new PracticeCtrl tenant. The invitation must be accepted through the same authorised application origin.</p>{tenantSlug?<BootstrapAdminForm tenantSlug={tenantSlug}/>:<p className="mt-6 rounded-xl bg-red-50 p-3 text-sm text-red-800">The tenant identifier is missing from this bootstrap link.</p>}</section></main>
}
