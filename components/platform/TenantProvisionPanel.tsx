"use client";
import { FormEvent, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type ProvisionResult={tenant?:{id:string;name:string;tenant_slug:string};bootstrapSecret?:string;bootstrapUrl?:string;expiresAt?:string;error?:string};
export function TenantProvisionPanel(){
  const supabase=useMemo(()=>createClient(),[]);
  const[busy,setBusy]=useState(false);
  const[result,setResult]=useState<ProvisionResult|null>(null);
  async function submit(e:FormEvent<HTMLFormElement>){
    e.preventDefault();setBusy(true);setResult(null);
    const f=new FormData(e.currentTarget);
    const body={name:String(f.get("name")||""),tenantSlug:String(f.get("tenantSlug")||""),legalName:String(f.get("legalName")||""),stagingOrigin:String(f.get("stagingOrigin")||"")};
    const{data,error}=await supabase.functions.invoke("practicectrl-tenant-provision",{body});
    setBusy(false);
    if(error)setResult({error:error.message}); else setResult(data as ProvisionResult);
    if(!error&&!data?.error)e.currentTarget.reset();
  }
  return <div className="grid gap-4 xl:grid-cols-[1fr_.8fr]">
    <form onSubmit={submit} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#4a1f3e]">Provision practice tenant</h3><p className="mt-1 text-sm text-stone-500">Creates the tenant boundary, default modules, staging origin and a one-time first-admin bootstrap secret. No clinical data is copied between tenants.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2"><input name="name" required placeholder="Practice display name" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/><input name="tenantSlug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" placeholder="practice-slug" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/><input name="legalName" placeholder="Legal name (optional)" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/><input name="stagingOrigin" type="url" required placeholder="https://staging.example.co.za" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/></div>
      <button disabled={busy} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">{busy?"Provisioning…":"Provision tenant"}</button>
    </form>
    <section className="rounded-2xl border border-stone-200 bg-stone-50 p-5"><h3 className="font-semibold text-[#4a1f3e]">Bootstrap handoff</h3>{result?.error?<p className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-800">{result.error}</p>:result?.tenant?<div className="mt-3 space-y-3 text-sm"><p><strong>{result.tenant.name}</strong> is provisioned.</p><div><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Bootstrap URL</p><p className="mt-1 break-all rounded-lg bg-white p-2 font-mono text-xs">{result.bootstrapUrl}</p></div><div><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">One-time secret</p><p className="mt-1 break-all rounded-lg bg-white p-2 font-mono text-xs">{result.bootstrapSecret}</p></div><p className="text-xs text-amber-700">Copy the secret now. Only its SHA-256 hash is stored and it cannot be recovered later. Expires {result.expiresAt?new Date(result.expiresAt).toLocaleString("en-ZA"):"according to the bootstrap policy"}.</p></div>:<p className="mt-3 text-sm text-stone-500">Provision a tenant to generate the controlled first-admin handoff.</p>}</section>
  </div>;
}
