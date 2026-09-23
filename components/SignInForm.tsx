"use client";

import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
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

  return <form onSubmit={submit} className="space-y-5">
    <label className="block text-sm font-semibold text-[#24364b]">
      Email
      <input name="email" type="email" required autoComplete="username" className="mt-1.5 w-full rounded-md border border-[#cbd5e1] bg-white px-3 py-2.5 text-[#12243b] placeholder:text-slate-400 focus:border-[#236cfb]" />
    </label>
    <label className="block text-sm font-semibold text-[#24364b]">
      Password
      <input name="password" type="password" required autoComplete="current-password" className="mt-1.5 w-full rounded-md border border-[#cbd5e1] bg-white px-3 py-2.5 text-[#12243b] placeholder:text-slate-400 focus:border-[#236cfb]" />
    </label>
    {error ? <p role="alert" className="rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">{error}</p> : null}
    <button disabled={busy} className="w-full rounded-md bg-[#067c80] px-4 py-3 font-semibold text-white hover:bg-[#056d70] disabled:cursor-not-allowed disabled:opacity-60">{busy ? "Signing in…" : "Sign in"}</button>
    <p className="text-center text-sm"><Link href="/auth/recover" className="font-medium text-[#067c80] underline">Set or reset your password</Link></p>
  </form>;
}
