"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function FinishRecovery({ inviteId }: { inviteId: string }) {
  const router = useRouter();
  const started = useRef(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (started.current) return;
    started.current = true;

    // The fragment is never sent to the server. Remove it before constructing
    // the SSR client, which otherwise tries to parse implicit tokens as PKCE.
    const fragment = new URLSearchParams(window.location.hash.slice(1));
    const accessToken = fragment.get("access_token");
    const refreshToken = fragment.get("refresh_token");
    window.history.replaceState(window.history.state, "", window.location.pathname + window.location.search);

    if (!accessToken || !refreshToken) {
      setError("This setup link is invalid or has expired. Request a new link from the account setup page.");
      return;
    }

    createClient().auth.setSession({ access_token: accessToken, refresh_token: refreshToken })
      .then(({ data, error: sessionError }) => {
        if (sessionError || !data.user) {
          setError("Could not verify this setup link. Request a new link from the account setup page.");
          return;
        }
        router.replace("/auth/set-password" + (inviteId ? "?invite=" + encodeURIComponent(inviteId) : ""));
        router.refresh();
      })
      .catch(() => setError("Could not verify this setup link. Request a new link from the account setup page."));
  }, [inviteId, router]);

  return <main className="mx-auto flex min-h-screen max-w-lg items-center px-5 py-12">
    <section className="w-full rounded-3xl border border-stone-200 bg-white p-7 shadow-sm">
      <p className="text-xs font-bold uppercase tracking-[.2em] text-[#067c80]">PracticeCtrl</p>
      <h1 className="mt-2 text-2xl font-semibold text-[#051a39]">Verifying your setup link</h1>
      {error ? <p role="alert" className="mt-5 rounded-xl bg-red-50 p-3 text-sm text-red-800">{error} <a className="underline" href={"/auth/recover" + (inviteId ? "?invite=" + encodeURIComponent(inviteId) : "")}>Account setup</a></p>
        : <p role="status" className="mt-4 text-sm text-stone-600">Checking your email confirmation…</p>}
    </section>
  </main>;
}
