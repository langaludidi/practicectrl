"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function AllocationPanel({ receipts, invoices }: {
  receipts: Array<{id:string;receipt_number:string;amount:number}>;
  invoices: Array<{id:string;invoice_number:string;balance_amount:number}>;
}) {
  const supabase=createClient(); const [msg,setMsg]=useState<string|null>(null); const [busy,setBusy]=useState(false);
  async function act(formData:FormData){setBusy(true);setMsg(null);const {error}=await supabase.rpc("allocate_billing_receipt",{p_receipt_id:String(formData.get("receiptId")),p_invoice_id:String(formData.get("invoiceId")),p_amount:Number(formData.get("amount")),p_claim_id:null,p_note:String(formData.get("note")||"")||null});setBusy(false);if(error)setMsg(error.message);else{setMsg("Receipt allocated.");window.location.reload();}}
  if(!receipts.length||!invoices.length) return null;
  return <form action={act} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm"><h3 className="font-semibold text-[#4a1f3e]">Allocate receipt to invoice</h3><div className="mt-4 grid gap-3 md:grid-cols-4"><select name="receiptId" className="rounded-xl border border-stone-300 px-3 py-2 text-sm">{receipts.map(r=><option key={r.id} value={r.id}>{r.receipt_number} · R{Number(r.amount).toFixed(2)}</option>)}</select><select name="invoiceId" className="rounded-xl border border-stone-300 px-3 py-2 text-sm">{invoices.map(i=><option key={i.id} value={i.id}>{i.invoice_number} · R{Number(i.balance_amount).toFixed(2)}</option>)}</select><input name="amount" type="number" min="0.01" step="0.01" required placeholder="Amount" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/><input name="note" placeholder="Allocation note" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"/></div><button disabled={busy} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Allocate</button>{msg?<p className="mt-3 text-sm text-stone-600">{msg}</p>:null}</form>;
}
