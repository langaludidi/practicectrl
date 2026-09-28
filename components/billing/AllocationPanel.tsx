"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Receipt = { id: string; receipt_number: string; amount: number };
type Invoice = { id: string; invoice_number: string; balance_amount: number };

export function AllocationPanel({ receipts, invoices }: { receipts: Receipt[]; invoices: Invoice[] }) {
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function allocate(formData: FormData) {
    setBusy(true);
    setMessage(null);
    const amount = Number(formData.get("amount"));
    if (!Number.isFinite(amount) || amount <= 0) {
      setMessage("Enter an allocation amount greater than zero.");
      setBusy(false);
      return;
    }
    try {
      const { error } = await createClient().rpc("allocate_billing_receipt", {
        p_receipt_id: String(formData.get("receiptId")),
        p_invoice_id: String(formData.get("invoiceId")),
        p_amount: amount,
        p_claim_id: null,
        p_note: String(formData.get("note") || "") || null,
      });
      if (error) throw error;
      window.location.reload();
    } catch {
      setMessage("The allocation could not be posted. Check the receipt balance and invoice, then try again.");
      setBusy(false);
    }
  }

  return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <h3 className="font-semibold text-[#051a39]">Allocate receipt to invoice</h3>
    {!receipts.length || !invoices.length ? <p className="mt-3 text-sm text-stone-600">
      {!receipts.length ? "Post a receipt before allocating a payment." : "There are no invoices with an outstanding balance to allocate."}
    </p> : <form action={allocate}>
      <p className="mt-1 text-sm text-stone-600">Select a receipt and an outstanding invoice. The allocation is recorded as a separate audited action.</p>
      <div className="mt-4 grid gap-3 md:grid-cols-4">
        <label className="text-xs font-medium text-stone-600">Receipt
          <select name="receiptId" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm">
            {receipts.map(receipt => <option key={receipt.id} value={receipt.id}>{receipt.receipt_number} · R{Number(receipt.amount).toFixed(2)}</option>)}
          </select>
        </label>
        <label className="text-xs font-medium text-stone-600">Invoice
          <select name="invoiceId" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm">
            {invoices.map(invoice => <option key={invoice.id} value={invoice.id}>{invoice.invoice_number} · R{Number(invoice.balance_amount).toFixed(2)}</option>)}
          </select>
        </label>
        <label className="text-xs font-medium text-stone-600">Amount (R)
          <input name="amount" type="number" min="0.01" step="0.01" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
        <label className="text-xs font-medium text-stone-600">Allocation note
          <input name="note" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
      </div>
      <button disabled={busy} className="mt-4 rounded-xl bg-[#067c80] px-4 py-2 text-sm font-medium text-white disabled:opacity-50">{busy ? "Allocating…" : "Allocate"}</button>
      {message ? <p role="alert" className="mt-3 rounded-xl bg-rose-50 p-3 text-sm text-rose-800">{message}</p> : null}
    </form>}
  </section>;
}
