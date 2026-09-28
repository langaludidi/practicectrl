"use client";

export default function BillingError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <section role="alert" className="rounded-xl border border-rose-200 bg-white p-6">
    <h1 className="text-xl font-semibold text-[#051a39]">Billing is temporarily unavailable</h1>
    <p className="mt-2 text-sm text-stone-600">Invoice and receipt information could not be loaded. Please try again or contact an administrator.</p>
    <button type="button" onClick={reset} className="mt-4 rounded-lg bg-[#067c80] px-4 py-2 text-sm font-semibold text-white">Try again</button>
  </section>;
}
