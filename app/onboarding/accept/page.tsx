import { Suspense } from "react";
import { AcceptInvitePanel } from "@/components/onboarding/AcceptInvitePanel";

export default function AcceptInvitePage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-lg items-center px-5 py-12">
      <section className="w-full rounded-3xl border border-stone-200 bg-white p-7 shadow-sm">
        <p className="text-xs font-bold uppercase tracking-[.2em] text-[#b84f45]">PracticeCtrl</p>
        <h1 className="mt-2 text-2xl font-semibold text-[#4a1f3e]">Accept staff invitation</h1>
        <p className="mt-2 text-sm text-stone-600">
          Confirm this invitation using the authenticated email session created by the invitation link.
        </p>
        <Suspense fallback={<p className="mt-5 text-sm text-stone-500">Loading invitation…</p>}>
          <AcceptInvitePanel />
        </Suspense>
      </section>
    </main>
  );
}
