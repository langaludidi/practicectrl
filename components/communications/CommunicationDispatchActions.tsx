"use client";
import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Readiness={ready?:boolean;reasons?:string[];warnings?:string[];provider_id?:string|null;environment?:string};

export function CommunicationDispatchActions({messageId,status}:{messageId:string;status:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const[busy,setBusy]=useState(false);
  const[result,setResult]=useState<Readiness|null>(null);
  const[msg,setMsg]=useState<string|null>(null);
  async function assess(){setBusy(true);setMsg(null);const{data,error}=await supabase.rpc("assess_communication_send_readiness",{p_message_id:messageId,p_environment:"staging"});setBusy(false);if(error){setMsg(error.message);return;}setResult((data||{}) as Readiness);}
  async function queue(){setBusy(true);setMsg(null);const{data,error}=await supabase.rpc("queue_communication_message",{p_message_id:messageId,p_environment:"staging"});setBusy(false);if(error){setMsg(error.message);return;}setMsg(`Queued through governed route: ${data}`);window.location.reload();}
  if(!["draft","failed"].includes(status))return null;
  return <div className="mt-2"><div className="flex gap-2"><button type="button" disabled={busy} onClick={assess} className="rounded-lg border px-2 py-1 text-xs">Assess send</button><button type="button" disabled={busy||result?.ready===false} onClick={queue} className="rounded-lg bg-[#4a1f3e] px-2 py-1 text-xs text-white disabled:opacity-40">Queue</button></div>{result?<div className={`mt-2 rounded-lg p-2 text-[11px] ${result.ready?"bg-emerald-50 text-emerald-900":"bg-amber-50 text-amber-900"}`}><p className="font-medium">{result.ready?"Ready to queue":"Not ready to queue"}</p>{(result.reasons||[]).map((x,i)=><p key={`r-${i}`} className="mt-1">• {x}</p>)}{(result.warnings||[]).map((x,i)=><p key={`w-${i}`} className="mt-1 text-stone-600">Warning: {x}</p>)}</div>:null}{msg?<p className="mt-2 max-w-xl break-words text-[11px] text-stone-600">{msg}</p>:null}</div>;
}
