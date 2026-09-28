"use client";

import { FormEvent, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Invoice = { id: string; invoice_number: string; status: string };
type Line = { id: string; invoice_id: string; line_no: number; description_snapshot: string; line_amount: number; code_system: string; metadata: any };

export function InvoiceLineControls({ invoices, lines }: { invoices: Invoice[]; lines: Line[] }) {
  const supabase = useMemo(() => createClient(), []);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const drafts = invoices.filter(invoice => invoice.status === "draft");

  async function add(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    const form = new FormData(event.currentTarget);
    const { error } = await supabase.rpc("add_practice_custom_invoice_line", {
      p_invoice_id: String(form.get("invoiceId")),
      p_description: String(form.get("description") || ""),
      p_amount: Number(form.get("amount")),
    });
    setBusy(false);
    if (error) setMessage(error.message);
    else window.location.reload();
  }

  async function remove(id: string) {
    const reason = window.prompt("Reason for removing this draft line") || "";
    if (reason.trim().length < 3) return;
    setBusy(true);
    const { error } = await supabase.rpc("remove_practice_custom_invoice_line", { p_invoice_line_id: id, p_reason: reason });
    setBusy(false);
    if (error) setMessage(error.message);
    else window.location.reload();
  }

  return <section className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
    <h3 className="font-semibold text-[#051a39]">Draft invoice workspace</h3>
    <p className="mt-1 text-sm text-stone-500">Only non-claimable PracticeCtrl custom lines can be added or removed, and only while the invoice is draft. Every change is audited.</p>
    {drafts.length ? <>
      <form onSubmit={add} className="mt-4 grid gap-3 sm:grid-cols-[220px_1fr_160px_auto] sm:items-end">
        <label className="text-xs font-medium text-stone-600">Draft invoice
          <select name="invoiceId" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm">{drafts.map(invoice => <option key={invoice.id} value={invoice.id}>{invoice.invoice_number}</option>)}</select>
        </label>
        <label className="text-xs font-medium text-stone-600">Line description
          <input name="description" required className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
        <label className="text-xs font-medium text-stone-600">Amount (R)
          <input name="amount" required type="number" min="0.01" step="0.01" className="mt-1 block w-full rounded-xl border border-stone-300 px-3 py-2 text-sm" />
        </label>
        <button disabled={busy} className="rounded-xl bg-[#067c80] px-4 py-2 text-sm font-medium text-white disabled:opacity-40">Add line</button>
      </form>
      <div className="mt-4 grid gap-2">{drafts.map(invoice => <div key={invoice.id} className="rounded-xl border border-stone-200 p-3">
        <p className="text-sm font-medium">{invoice.invoice_number}</p>
        {lines.filter(line => line.invoice_id === invoice.id).map(line => <div key={line.id} className="mt-2 flex items-center justify-between gap-3 text-xs">
          <span>{line.line_no}. {line.description_snapshot} · R{Number(line.line_amount).toFixed(2)} · {line.code_system}</span>
          {line.code_system === "PRACTICE_CUSTOM" && line.metadata?.claim_eligible === false ? <button type="button" onClick={() => remove(line.id)} disabled={busy} className="rounded-lg border px-2 py-1">Remove</button> : null}
        </div>)}
      </div>)}</div>
    </> : <p className="mt-4 text-sm text-stone-500">No draft invoices available for editing. Create a draft above to add invoice lines.</p>}
    {message ? <p role="alert" className="mt-3 rounded-xl bg-rose-50 p-3 text-sm text-rose-800">{message}</p> : null}
  </section>;
}
