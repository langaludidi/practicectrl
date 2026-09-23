"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { PracticeMembership } from "@/lib/auth/server";

export function PracticeSelector({ memberships, preferredPracticeId }: { memberships: PracticeMembership[]; preferredPracticeId: string | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function choose(practiceId: string) {
    setBusy(practiceId);
    setError(null);
    try {
      const response = await fetch("/api/practice-context", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ practiceId }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body?.error || "Could not select practice.");
      router.replace(body?.next || "/dashboard");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not select practice.");
      setBusy(null);
    }
  }

  return <div className="grid gap-3">
    {memberships.map((membership) => <button
      key={membership.practiceId}
      type="button"
      disabled={busy !== null}
      onClick={() => choose(membership.practiceId)}
      className="rounded-2xl border border-stone-200 bg-white p-4 text-left shadow-sm transition hover:border-[#b84f45] hover:shadow disabled:opacity-50"
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="font-semibold text-[#4a1f3e]">{membership.practiceName}</p>
          <p className="mt-1 text-xs text-stone-500">{membership.tenantSlug} · {membership.role.replaceAll("_", " ")}</p>
        </div>
        {preferredPracticeId === membership.practiceId ? <span className="rounded-full bg-stone-100 px-2.5 py-1 text-xs text-stone-600">Last used</span> : null}
      </div>
      <p className="mt-3 text-xs font-medium text-[#b84f45]">{busy === membership.practiceId ? "Opening…" : "Open practice"}</p>
    </button>)}
    {error ? <p className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{error}</p> : null}
  </div>;
}
