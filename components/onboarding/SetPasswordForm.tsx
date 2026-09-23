"use client";
import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function SetPasswordForm({inviteId}:{inviteId:string}){
  const router=useRouter();const[busy,setBusy]=useState(false);const[error,setError]=useState<string|null>(null);
  async function submit(event:FormEvent<HTMLFormElement>){
    event.preventDefault();setBusy(true);setError(null);
    const form=new FormData(event.currentTarget);
    const password=String(form.get("password")||"");
    if(password!==String(form.get("confirm")||"")){setBusy(false);setError("The passwords do not match.");return;}
    const supabase=createClient();
    const {data:userData,error:userError}=await supabase.auth.getUser();
    if(userError||!userData.user){setBusy(false);setError("Open the password setup link from your email first.");return;}
    const {error:updateError}=await supabase.auth.updateUser({password});
    setBusy(false);
    if(updateError){setError("Could not set your password. Please request a fresh setup link.");return;}
    router.replace(inviteId?"/onboarding/accept?invite="+encodeURIComponent(inviteId):"/select-practice");
    router.refresh();
  }
  return <form onSubmit={submit} className="mt-6 space-y-4">
    <label className="block text-sm font-medium text-stone-700">New password
      <input name="password" type="password" minLength={12} required autoComplete="new-password" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5"/>
    </label>
    <label className="block text-sm font-medium text-stone-700">Confirm password
      <input name="confirm" type="password" minLength={12} required autoComplete="new-password" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5"/>
    </label>
    <button disabled={busy} className="w-full rounded-xl bg-[#067c80] px-4 py-2.5 font-semibold text-white disabled:opacity-50">{busy?"Saving…":"Set password and continue"}</button>
    {error?<p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{error}</p>:null}
  </form>;
}
