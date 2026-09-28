import { MfaGate } from "@/components/MfaGate";
import { requireStaffIdentity } from "@/lib/auth/server";

export default async function MfaPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const staff = await requireStaffIdentity();
  const { next } = await searchParams;
  const destination = staff.platformRole && next === "/platform/tenants" ? "/platform/tenants" : "/dashboard";
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <section className="w-full max-w-md rounded-3xl border border-stone-200 bg-white p-8 shadow-sm">
        <p className="text-xs font-bold tracking-[.2em] text-[#067c80]">PRACTICECTRL</p>
        <h1 className="mt-3 text-3xl font-semibold text-[#051a39]">Security verification</h1>
        <p className="mb-7 mt-2 text-sm text-stone-600">PracticeCtrl requires multi-factor authentication before staff can enter the selected practice.</p>
        <MfaGate email={staff.email} destination={destination} />
      </section>
    </main>
  );
}
