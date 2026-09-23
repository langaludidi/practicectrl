import Link from "next/link";
import { PracticeSelector } from "@/components/PracticeSelector";
import { getPracticeSelectionContext } from "@/lib/auth/server";

export default async function SelectPracticePage() {
  const identity = await getPracticeSelectionContext();
  return <main className="mx-auto flex min-h-screen max-w-2xl items-center px-5 py-12">
    <section className="w-full rounded-3xl border border-stone-200 bg-stone-50 p-6 shadow-sm sm:p-8">
      <p className="text-xs font-bold uppercase tracking-[.2em] text-[#b84f45]">PracticeCtrl</p>
      <h1 className="mt-2 text-3xl font-semibold text-[#4a1f3e]">Choose your practice</h1>
      <p className="mt-2 text-sm text-stone-600">Your role, records, integrations and workflows are isolated per practice. PracticeCtrl validates membership again when you switch.</p>
      <div className="mt-6">
        {identity.memberships.length ? <PracticeSelector memberships={identity.memberships} preferredPracticeId={identity.preferredPracticeId}/> : <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">No active practice membership is attached to {identity.email ?? "this account"}. Check pending invitations or contact the practice administrator.</div>}
      </div>
      <div className="mt-6 flex flex-wrap gap-3 text-sm">
        <Link href="/invitations" className="font-medium text-[#4a1f3e] underline underline-offset-4">Pending invitations</Link>
        {identity.platformRole ? <Link href="/platform/tenants" className="font-medium text-[#4a1f3e] underline underline-offset-4">Platform console</Link> : null}
      </div>
    </section>
  </main>;
}
