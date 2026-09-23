"use client";
import { FormEvent, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function RecoveryForm({inviteId}:{inviteId:string}){
  const[busy,setBusy]=useState(false);const[message,setMessage]=useState<string|null>(null);const[error,setError]=useState<string|null>(null);
  async function submit(event:FormEvent<HTMLFormElement>){
    event.preventDefault();setBusy(true);setMessage(null);setError(null);
    const email=String(new FormData(event.currentTarget).get("email")||"").trim();
    const next="/auth/set-password"+(inviteId?"?invite="+encodeURIComponent(inviteId):"");
    const callback=new URL("/auth/callback",window.location.origin);
    callback.searchParams.set("next",next);
    const {error:requestError}=await createClient().auth.resetPasswordForEmail(email,{redirectTo:callback.toString()});
    setBusy(false);
    if(requestError){setError("Could not send the account setup email. Please try again.");return;}
    setMessage("If this account exists, a password setup link has been sent. Open it on this device to continue.");
  }
  return <form onSubmit={submit} className="mt-6 space-y-4">
    <label className="block text-sm font-medium text-stone-700">Administrator email
      <input name="email" type="email" required autoComplete="email" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5"/>
    </label>
    <button disabled={busy} className="w-full rounded-xl bg-[#067c80] px-4 py-2.5 font-semibold text-white disabled:opacity-50">{busy?"Sending…":"Email me a password setup link"}</button>
    {error?<p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{error}</p>:null}
    {message?<p role="status" className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p>:null}
  </form>;
}
