"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function BillingActions({ practiceId, patients, invoices }: {
  practiceId: string;
  patients: Array<{ id: string; display_name: string }>;
  invoices: Array<{ id: string; invoice_number: string; balance_amount: number; status: string }>;
}) {
  const supabase = createClient();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function createInvoice(formData: FormData) {
    setBusy(true); setMessage(null);
    const amount = Number(formData.get("amount"));
    const patientId = String(formData.get("patientId") || "") || null;
    const description = String(formData.get("description") || "").trim();
    const patientPortion = Number(formData.get("patientPortion") || amount);
    const schemePortion = Number(formData.get("schemePortion") || 0);
    const { data, error } = await supabase.rpc("create_practice_custom_invoice", {
      p_practice_id: practiceId,
      p_patient_id: patientId,
      p_invoice_date: new Date().toISOString().slice(0,10),
      p_description: description,
      p_amount: amount,
      p_patient_portion: patientPortion,
      p_scheme_portion: schemePortion,
    });
    setBusy(false);
    if (error) setMessage(error.message); else { setMessage(`Draft invoice created: ${data}`); window.location.reload(); }
  }

  async function finalise(invoiceId: string) {
    setBusy(true); setMessage(null);
    const { error } = await supabase.rpc("finalise_billing_invoice", { p_invoice_id: invoiceId });
    setBusy(false);
    if (error) setMessage(error.message); else { setMessage("Invoice finalised after automated claim pre-flight passed."); window.location.reload(); }
  }

  async function createReceipt(formData: FormData) {
    setBusy(true); setMessage(null);
    const amount = Number(formData.get("amount"));
    const patientId = String(formData.get("patientId") || "") || null;
    const { data, error } = await supabase.rpc("create_billing_receipt", {
      p_practice_id: practiceId,
      p_patient_id: patientId,
      p_medical_scheme_id: null,
      p_payer_type: String(formData.get("payerType") || "patient"),
      p_receipt_number: String(formData.get("receiptNumber") || "").trim(),
      p_receipt_date: String(formData.get("receiptDate") || new Date().toISOString().slice(0,10)),
      p_amount: amount,
      p_payment_method: String(formData.get("paymentMethod") || "") || null,
      p_external_reference: String(formData.get("externalReference") || "") || null,
    });
    setBusy(false);
    if (error) setMessage(error.message); else { setMessage(`Receipt posted: ${data}`); window.location.reload(); }
  }

  async function allocate(formData: FormData) {
    setBusy(true); setMessage(null);
    const { data, error } = await supabase.rpc("allocate_billing_receipt", {
      p_receipt_id: String(formData.get("receiptId")),
      p_invoice_id: String(formData.get("invoiceId")),
      p_amount: Number(formData.get("amount")),
      p_claim_id: null,
      p_note: String(formData.get("note") || "") || null,
    });
    setBusy(false);
    if (error) setMessage(error.message); else { setMessage(`Allocation posted: ${data}`); window.location.reload(); }
  }

  return <div className="grid gap-4 xl:grid-cols-2">
    <form action={createInvoice} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#4a1f3e]">Create controlled draft invoice</h3>
      <p className="mt-1 text-sm text-stone-500">PracticeCtrl custom drafts are not automatically claim-eligible.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <select name="patientId" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">No patient link</option>{patients.map(p=><option key={p.id} value={p.id}>{p.display_name}</option>)}</select>
        <input name="amount" type="number" min="0.01" step="0.01" required placeholder="Total amount" className="rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        <input name="patientPortion" type="number" min="0" step="0.01" placeholder="Patient portion" className="rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        <input name="schemePortion" type="number" min="0" step="0.01" placeholder="Scheme portion" className="rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        <input name="description" required placeholder="Service / invoice description" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2" />
      </div>
      <button disabled={busy} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Create draft</button>
    </form>

    <form action={createReceipt} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#4a1f3e]">Post receipt</h3>
      <p className="mt-1 text-sm text-stone-500">Receipt posting and invoice allocation are separate audited actions.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <input name="receiptNumber" required placeholder="Receipt number" className="rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        <input name="receiptDate" type="date" defaultValue={new Date().toISOString().slice(0,10)} required className="rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        <select name="patientId" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="">No patient link</option>{patients.map(p=><option key={p.id} value={p.id}>{p.display_name}</option>)}</select>
        <select name="payerType" className="rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="patient">Patient</option><option value="scheme">Scheme</option><option value="insurer">Insurer</option><option value="other">Other</option></select>
        <input name="amount" type="number" min="0.01" step="0.01" required placeholder="Receipt amount" className="rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        <input name="paymentMethod" placeholder="EFT / Cash / Card" className="rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        <input name="externalReference" placeholder="Bank / external reference" className="rounded-xl border border-stone-300 px-3 py-2 text-sm sm:col-span-2" />
      </div>
      <button disabled={busy} className="mt-4 rounded-xl bg-[#4a1f3e] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Post receipt</button>
    </form>

    <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm xl:col-span-2">
      <h3 className="font-semibold text-[#4a1f3e]">Invoice actions</h3>
      <div className="mt-4 flex flex-wrap gap-2">{invoices.filter(i=>i.status==="draft").slice(0,8).map(i=><button key={i.id} type="button" disabled={busy} onClick={()=>finalise(i.id)} className="rounded-xl border border-stone-300 bg-white px-3 py-2 text-sm hover:bg-stone-50">Finalise {i.invoice_number}</button>)}</div>
      {message ? <p className="mt-4 rounded-xl bg-stone-50 p-3 text-sm text-stone-700">{message}</p> : null}
    </div>
  </div>;
}
