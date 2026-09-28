"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const OPTIONS = ["New", "Contacted", "Alternative Offered", "Unable to Reach", "Confirmed in PMS", "Closed", "Duplicate"];

export function RequestStatusActions({ id, status }: { id: string; status: string }) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [next, setNext] = useState(status);
  const [reference, setReference] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  useEffect(() => { setNext(status); }, [status]);
  if (status === "Booked in PracticeCtrl") return <span className="text-xs text-stone-600">Booked in PracticeCtrl (historical)</span>;
  if (status === "Confirmed in PMS") return <span className="text-xs text-stone-600">Confirmed in PMS</span>;

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const pmsReference = reference.trim();
    if (next === status) return;
    if (next === "Confirmed in PMS" && !pmsReference) {
      setMessage("Enter the appointment reference from the PMS before confirming.");
      return;
    }
    setBusy(true);
    setMessage(null);
    const { error } = await supabase.rpc("update_appointment_request_status", {
      p_request_id: id,
      p_status: next,
      p_pms_reference: next === "Confirmed in PMS" ? pmsReference : null,
    });
    setBusy(false);
    if (error) setMessage(error.message);
    else {
      setReference("");
      setMessage("Request updated.");
      router.refresh();
    }
  }

  return <form onSubmit={submit} className="grid min-w-44 gap-2">
    <label className="text-xs text-stone-600">Request status
      <select disabled={busy} value={next} onChange={event => { setNext(event.target.value); setMessage(null); }} className="mt-1 block w-full rounded-lg border border-stone-300 bg-white px-2 py-1.5 text-xs">
        {OPTIONS.map(option => <option key={option} value={option}>{option}</option>)}
      </select>
    </label>
    {next === "Confirmed in PMS" && <label className="text-xs text-stone-600">PMS appointment reference
      <input autoComplete="off" value={reference} onChange={event => setReference(event.target.value)} required maxLength={120} placeholder="Reference from the PMS" className="mt-1 block w-full rounded-lg border border-stone-300 px-2 py-1.5 text-xs" />
    </label>}
    {next !== status && <button disabled={busy} type="submit" className="rounded-lg bg-[#067c80] px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50">{busy ? "Saving…" : "Save status"}</button>}
    {message && <p role="status" className="text-xs text-stone-700">{message}</p>}
  </form>;
}
