"use client";

import { FormEvent, useState } from "react";
import { createClient } from "@supabase/supabase-js";

export function RecoveryForm({ inviteId }: { inviteId: string }) {
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function requestLink(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setMessage(null);
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!url || !key) {
      setBusy(false);
      setError("Account setup is temporarily unavailable. Please try again later.");
      return;
    }
    // A recovery email can open in another browser, where a PKCE verifier from this
    // browser would be unavailable. The default Supabase email supports this flow.
    const recovery = createClient(url, key, {
      auth: { flowType: "implicit", persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const next = "/auth/set-password" + (inviteId ? "?invite=" + encodeURIComponent(inviteId) : "");
    const callback = new URL("/auth/callback", window.location.origin);
    callback.searchParams.set("next", next);
    const { error: requestError } = await recovery.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: callback.toString(),
    });
    setBusy(false);
    if (requestError) {
      setError(requestError.status === 429
        ? "Supabase has temporarily limited setup emails. Wait before requesting another link."
        : "Could not send the account setup email. Please try again later.");
      return;
    }
    setMessage("If this account exists, a password setup link has been sent. Open the newest email and follow its link to choose your password.");
  }

  return <div className="mt-6 space-y-5">
    <form onSubmit={requestLink} className="space-y-4">
      <label className="block text-sm font-medium text-stone-700">Administrator email
        <input name="email" type="email" value={email} onChange={event => setEmail(event.target.value)} required autoComplete="email" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5" />
      </label>
      <button disabled={busy} className="w-full rounded-xl bg-[#067c80] px-4 py-2.5 font-semibold text-white disabled:opacity-50">{busy ? "Sending…" : "Email me a password setup link"}</button>
    </form>
    {error ? <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{error}</p> : null}
    {message ? <p role="status" className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p> : null}
  </div>;
}
