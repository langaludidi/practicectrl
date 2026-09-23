"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function RecoveryForm({ inviteId }: { inviteId: string }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function requestCode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setMessage(null);
    const { error: requestError } = await createClient().auth.resetPasswordForEmail(email.trim());
    setBusy(false);
    if (requestError) {
      setError(requestError.status === 429
        ? "Supabase has temporarily limited setup emails. Use a code already in your latest email, or wait before requesting another."
        : "Could not send the account setup email. Please try again later.");
      return;
    }
    setMessage("If this account exists, a six-digit setup code has been emailed to you. Enter the code below.");
  }

  async function verifyCode(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setVerifying(true);
    setError(null);
    const code = String(new FormData(event.currentTarget).get("code") || "").trim();
    const { error: verifyError } = await createClient().auth.verifyOtp({
      email: email.trim(), token: code, type: "recovery",
    });
    setVerifying(false);
    if (verifyError) {
      setError("The code could not be verified. Check the latest email and try again, or request a new code when email sending is available.");
      return;
    }
    router.replace("/auth/set-password" + (inviteId ? "?invite=" + encodeURIComponent(inviteId) : ""));
    router.refresh();
  }

  return <div className="mt-6 space-y-5">
    <form onSubmit={requestCode} className="space-y-4">
      <label className="block text-sm font-medium text-stone-700">Administrator email
        <input name="email" type="email" value={email} onChange={event => setEmail(event.target.value)} required autoComplete="email" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5" />
      </label>
      <button disabled={busy} className="w-full rounded-xl bg-[#067c80] px-4 py-2.5 font-semibold text-white disabled:opacity-50">{busy ? "Sending…" : "Email me a setup code"}</button>
    </form>
    <form onSubmit={verifyCode} className="space-y-4 border-t border-stone-200 pt-5">
      <label className="block text-sm font-medium text-stone-700">Six-digit code from your email
        <input name="code" type="text" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5" />
      </label>
      <button disabled={verifying || !email.trim()} className="w-full rounded-xl border border-[#067c80] px-4 py-2.5 font-semibold text-[#067c80] disabled:opacity-50">{verifying ? "Checking…" : "Verify code and set password"}</button>
    </form>
    {error ? <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{error}</p> : null}
    {message ? <p role="status" className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p> : null}
  </div>;
}
