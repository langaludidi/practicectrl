"use client";
import { FormEvent, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

async function functionErrorMessage(error:{message:string;context?:unknown}|null,data:{error?:string}|null,fallback:string){
  if(data?.error)return data.error;
  if(error?.context instanceof Response){
    try{const body=await error.context.clone().json();if(typeof body?.error==="string")return body.error;}catch{}
  }
  return error?.message||fallback;
}

export function BootstrapAdminForm({ tenantSlug }: { tenantSlug:string }){
  const supabase=useMemo(()=>createClient(),[]);
  const[busy,setBusy]=useState(false);const[msg,setMsg]=useState<string|null>(null);const[error,setError]=useState<string|null>(null);
  async function submit(e:FormEvent<HTMLFormElement>){
    e.preventDefault();setBusy(true);setMsg(null);setError(null);
    const form=e.currentTarget;const fd=new FormData(form);const email=String(fd.get("email")||"");const bootstrapToken=String(fd.get("bootstrapToken")||"").trim();const origin=window.location.origin;
    const reg=await supabase.functions.invoke("practicectrl-bootstrap-invite",{body:{action:"register_origin",tenantSlug,bootstrapToken,origin}});
    if(reg.error||reg.data?.error){setBusy(false);setError(await functionErrorMessage(reg.error,reg.data,"Staging origin registration failed."));return;}
    const inv=await supabase.functions.invoke("practicectrl-bootstrap-invite",{body:{action:"invite",tenantSlug,email,bootstrapToken}});
    setBusy(false);if(inv.error||inv.data?.error){setError(await functionErrorMessage(inv.error,inv.data,"Bootstrap invitation failed."));return;}
    setMsg(inv.data.message||"First-administrator invitation sent.");form.reset();
  }
  return <form onSubmit={submit} className="mt-6 space-y-4">
    <div className="rounded-xl border border-sky-100 bg-sky-50 p-3 text-xs text-sky-900"><strong>Two-stage protected bootstrap.</strong> PracticeCtrl first registers this exact HTTPS deployment origin using the one-time secret, then sends the first system-administrator invitation. No database-origin workaround is required.</div>
    <label className="block text-sm font-medium text-stone-700">Administrator email<input name="email" type="email" required className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5"/></label>
    <label className="block text-sm font-medium text-stone-700">One-time bootstrap secret<input name="bootstrapToken" type="password" minLength={24} required autoComplete="off" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2.5"/></label>
    <button disabled={busy} className="w-full rounded-xl bg-[#4a1f3e] px-4 py-2.5 font-semibold text-white disabled:opacity-50">{busy?"Securing staging…":"Register staging & invite administrator"}</button>
    {error?<p className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{error}</p>:null}{msg?<p className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{msg}</p>:null}
    <p className="text-xs text-stone-500">The secret is high-entropy, expiry-controlled and rate-limited. It is consumed only when the bootstrap administrator accepts the invitation. A different staging origin cannot silently replace an active one.</p>
  </form>;
}
