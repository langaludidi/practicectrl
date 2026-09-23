"use client";

import { FormEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Dataset = {
  id:string; name:string; dataset_key:string; domain:string; access_model:string;
  licence_required:boolean; versioned_required:boolean; status:string;
};
type Release = { id:string; dataset_id:string; release_name:string; version:string|null; status:string; licence_reference:string|null; source_file_id:string|null };

export function GovernedSourcePanel({datasets,releases}:{datasets:Dataset[];releases:Release[]}) {
  const supabase=useMemo(()=>createClient(),[]); const router=useRouter();
  const [draftBusy,setDraftBusy]=useState(false); const [uploadBusy,setUploadBusy]=useState(false);
  const [message,setMessage]=useState<string|null>(null); const [error,setError]=useState<string|null>(null);
  const [uploadDataset,setUploadDataset]=useState(datasets[0]?.id||"");
  const availableReleases=releases.filter(r=>r.dataset_id===uploadDataset&&r.status==="pending_review"&&!r.source_file_id);

  async function createRelease(event:FormEvent<HTMLFormElement>){
    event.preventDefault(); setDraftBusy(true); setMessage(null); setError(null);
    const fd=new FormData(event.currentTarget);
    const body={
      datasetId:String(fd.get("datasetId")||""), releaseName:String(fd.get("releaseName")||""),
      version:String(fd.get("version")||"")||null, publishedDate:String(fd.get("publishedDate")||"")||null,
      effectiveFrom:String(fd.get("effectiveFrom")||"")||null, effectiveTo:String(fd.get("effectiveTo")||"")||null,
      sourceUri:String(fd.get("sourceUri")||"")||null, licenceReference:String(fd.get("licenceReference")||"")||null,
      notes:String(fd.get("notes")||"")||null,
    };
    const {data,error:e}=await supabase.functions.invoke("practicectrl-source-release-draft",{body});
    setDraftBusy(false); if(e){setError(e.message);return;} if(data?.error){setError(data.error);return;}
    setMessage("Pending governed release created. No dataset was activated."); event.currentTarget.reset(); router.refresh();
  }

  async function upload(event:FormEvent<HTMLFormElement>){
    event.preventDefault(); setUploadBusy(true); setMessage(null); setError(null);
    const body=new FormData(event.currentTarget);
    const {data,error:e}=await supabase.functions.invoke("practicectrl-source-upload",{body});
    setUploadBusy(false); if(e){setError(e.message);return;} if(data?.error){setError(data.error);return;}
    setMessage(`Source registered with SHA-256 ${data?.sourceFile?.sha256||"confirmed"}. Upload did not activate the release.`);
    event.currentTarget.reset(); router.refresh();
  }

  return <div className="grid gap-4 xl:grid-cols-2">
    <form onSubmit={createRelease} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#4a1f3e]">Create governed release draft</h3>
      <p className="mt-1 text-sm text-stone-500">Release metadata is reviewed before source bytes can be validated or activated.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <select name="datasetId" required className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2">{datasets.map(d=><option key={d.id} value={d.id}>{d.name} · {d.domain}{d.licence_required?" · licensed":""}</option>)}</select>
        <input name="releaseName" required placeholder="Release name" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
        <input name="version" placeholder="Version / distribution" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
        <label className="text-xs text-stone-500">Published date<input name="publishedDate" type="date" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2 text-sm text-stone-800"/></label>
        <label className="text-xs text-stone-500">Effective from<input name="effectiveFrom" type="date" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2 text-sm text-stone-800"/></label>
        <label className="text-xs text-stone-500">Effective to<input name="effectiveTo" type="date" className="mt-1 w-full rounded-xl border border-stone-300 px-3 py-2 text-sm text-stone-800"/></label>
        <input name="licenceReference" placeholder="Licence reference (required for licensed data)" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
        <input name="sourceUri" placeholder="Authoritative source URL / portal reference" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/>
        <textarea name="notes" rows={2} placeholder="Review notes" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2"/>
      </div>
      <button disabled={draftBusy||!datasets.length} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">{draftBusy?"Creating…":"Create pending release"}</button>
    </form>

    <form onSubmit={upload} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#4a1f3e]">Register immutable source file</h3>
      <p className="mt-1 text-sm text-stone-500">The trusted upload function computes SHA-256 and stores the exact bytes in the private governed bucket. Upload is never activation.</p>
      <div className="mt-4 grid gap-3">
        <select name="datasetId" value={uploadDataset} onChange={(e:any)=>setUploadDataset(e.target.value)} required className="rounded-xl border border-stone-300 px-3 py-2 text-sm">{datasets.map(d=><option key={d.id} value={d.id}>{d.name}{d.licence_required?" · licensed":""}</option>)}</select>
        <select name="releaseId" defaultValue="" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">No release link (public/non-licensed datasets only)</option>{availableReleases.map(r=><option key={r.id} value={r.id}>{r.release_name}{r.version?` · ${r.version}`:""}{r.licence_reference?" · licence recorded":""}</option>)}</select>
        <input name="sourceUri" placeholder="Source URL / portal reference" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/>
        <input name="file" type="file" required accept=".pdf,.xlsx,.xls,.csv,.xml,.json,.txt" className="rounded-xl border border-stone-300 bg-stone-50 px-3 py-2 text-sm"/>
      </div>
      <button disabled={uploadBusy||!datasets.length} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">{uploadBusy?"Hashing and registering…":"Register source file"}</button>
      <p className="mt-3 text-xs text-stone-500">Licensed datasets cannot accept bytes until a governed release already contains a licence reference.</p>
    </form>
    {error?<p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800 xl:col-span-2">{error}</p>:null}
    {message?<p role="status" className="break-all rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800 xl:col-span-2">{message}</p>:null}
  </div>;
}
