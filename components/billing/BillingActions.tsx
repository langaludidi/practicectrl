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
    const schemePortion = Number(formData.get("schemePortion") || 0);
    const patientPortionInput = String(formData.get("patientPortion") || "").trim();
    const patientPortion = patientPortionInput ? Number(patientPortionInput) : Math.round((amount - schemePortion) * 100) / 100;
    if (!patientId) {
      setMessage("Select a patient before creating an invoice.");
      setBusy(false);
      return;
    }
    if (!Number.isFinite(amount) || amount <= 0 || !Number.isFinite(patientPortion) || !Number.isFinite(schemePortion)
      || patientPortion < 0 || schemePortion < 0 || Math.abs(patientPortion + schemePortion - amount) > 0.009) {
      setMessage("Patient and scheme portions must add up to the invoice total.");
      setBusy(false);
      return;
    }
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
    if (!patientId) {
      setMessage("Select a patient before posting a patient receipt.");
      setBusy(false);
      return;
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      setMessage("Enter a receipt amount greater than zero.");
      setBusy(false);
      return;
    }
    const { data, error } = await supabase.rpc("create_billing_receipt", {
      p_practice_id: practiceId,
      p_patient_id: patientId,
      p_medical_scheme_id: null,
      p_payer_type: "patient",
      p_receipt_number: String(formData.get("receiptNumber") || "").trim(),
      p_receipt_date: String(formData.get("receiptDate") || new Date().toISOString().slice(0,10)),
      p_amount: amount,
      p_payment_method: String(formData.get("paymentMethod") || "") || null,
      p_external_reference: String(formData.get("externalReference") || "") || null,
    });
    setBusy(false);
    if (error) setMessage(error.message); else { setMessage(`Receipt posted: ${data}`); window.location.reload(); }
  }

  return <div className="grid gap-4 xl:grid-cols-2">
    <form action={createInvoice} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#051a39]">Create controlled draft invoice</h3>
      <p className="mt-1 text-sm text-stone-500">Select an active patient. PracticeCtrl custom drafts are not automatically claim-eligible.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-xs font-medium text-stone-600">Patient
          <select name="patientId" required defaultValue="" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="" disabled>Select a patient</option>{patients.map(p=><option key={p.id} value={p.id}>{p.display_name}</option>)}</select>
        </label>
        <label className="text-xs font-medium text-stone-600">Total amount (R)
          <input name="amount" type="number" min="0.01" step="0.01" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
        <label className="text-xs font-medium text-stone-600">Patient portion (R)
          <input name="patientPortion" type="number" min="0" step="0.01" placeholder="Calculated if blank" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
        <label className="text-xs font-medium text-stone-600">Scheme portion (R)
          <input name="schemePortion" type="number" min="0" step="0.01" placeholder="0.00" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
        <label className="text-xs font-medium text-stone-600 sm:col-span-2">Service / invoice description
          <input name="description" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
      </div>
      <button disabled={busy || !patients.length} className="mt-4 rounded-xl bg-[#067c80] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Create draft</button>
      {!patients.length ? <p className="mt-2 text-xs text-stone-600">Add an active patient before creating a draft invoice.</p> : null}
    </form>

    <form action={createReceipt} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
      <h3 className="font-semibold text-[#051a39]">Post patient receipt</h3>
      <p className="mt-1 text-sm text-stone-500">Select a patient. This form posts patient receipts only. Receipt posting and invoice allocation are separate audited actions.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-xs font-medium text-stone-600">Receipt number<input name="receiptNumber" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" /></label>
        <label className="text-xs font-medium text-stone-600">Receipt date<input name="receiptDate" type="date" defaultValue={new Date().toISOString().slice(0,10)} required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" /></label>
        <label className="text-xs font-medium text-stone-600">Patient<select name="patientId" required defaultValue="" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm"><option value="" disabled>Select a patient</option>{patients.map(p=><option key={p.id} value={p.id}>{p.display_name}</option>)}</select></label>
        <label className="text-xs font-medium text-stone-600">Receipt amount (R)<input name="amount" type="number" min="0.01" step="0.01" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" /></label>
        <label className="text-xs font-medium text-stone-600">Payment method<input name="paymentMethod" placeholder="EFT / Cash / Card" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" /></label>
        <label className="text-xs font-medium text-stone-600 sm:col-span-2">Bank / external reference<input name="externalReference" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" /></label>
      </div>
      <button disabled={busy || !patients.length} className="mt-4 rounded-xl bg-[#067c80] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">Post receipt</button>
    </form>

    <div className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm xl:col-span-2">
      <h3 className="font-semibold text-[#051a39]">Invoice actions</h3>
      <div className="mt-4 flex flex-wrap gap-2">{invoices.filter(i=>i.status==="draft").slice(0,8).map(i=><button key={i.id} type="button" disabled={busy} onClick={()=>finalise(i.id)} className="rounded-xl border border-stone-300 bg-white px-3 py-2 text-sm hover:bg-stone-50">Finalise {i.invoice_number}</button>)}</div>
      {!invoices.some(i=>i.status==="draft") ? <p className="mt-4 text-sm text-stone-500">No draft invoices are ready for finalisation.</p> : null}
      {message ? <p role="status" className="mt-4 rounded-xl bg-stone-50 p-3 text-sm text-stone-700">{message}</p> : null}
    </div>
  </div>;
}
