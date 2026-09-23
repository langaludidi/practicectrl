import { MfaGate } from "@/components/MfaGate";
import { requireStaffIdentity } from "@/lib/auth/server";

export default async function MfaPage() {
  const staff = await requireStaffIdentity();
  return (
    <main className="grid min-h-screen place-items-center p-6">
      <section className="w-full max-w-md rounded-3xl border border-stone-200 bg-white p-8 shadow-sm">
        <p className="text-xs font-bold tracking-[.2em] text-[#e5533d]">PRACTICECTRL</p>
        <h1 className="mt-3 text-3xl font-semibold text-[#4a1f3e]">Security verification</h1>
        <p className="mb-7 mt-2 text-sm text-stone-600">PracticeCtrl requires multi-factor authentication before staff can enter the selected practice.</p>
        <MfaGate email={staff.email} />
      </section>
    </main>
  );
}
