"use client";
import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function SignInForm() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const form = new FormData(event.currentTarget);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({
      email: String(form.get("email") ?? ""),
      password: String(form.get("password") ?? ""),
    });
    if (error) {
      setBusy(false);
      return setError("Sign-in failed. Check your details and try again.");
    }

    setBusy(false);
    router.replace("/select-practice");
    router.refresh();
  }

  return <form onSubmit={submit} className="space-y-4">
    <label className="block text-sm font-medium">Email<input name="email" type="email" required autoComplete="username" className="mt-1 w-full rounded-xl border border-stone-300 bg-white px-3 py-2.5" /></label>
    <label className="block text-sm font-medium">Password<input name="password" type="password" required autoComplete="current-password" className="mt-1 w-full rounded-xl border border-stone-300 bg-white px-3 py-2.5" /></label>
    {error && <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-800">{error}</p>}
    <button disabled={busy} className="w-full rounded-xl bg-[#4a1f3e] px-4 py-3 font-semibold text-white disabled:opacity-60">{busy ? "Signing in…" : "Sign in"}</button>
  </form>;
}
