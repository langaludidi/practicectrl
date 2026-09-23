export function StatusPill({ value }: { value: string | null | undefined }) {
  const text = value || "unknown";
  const normalized = text.toLowerCase().replaceAll("_", " ");
  const good = ["paid","resolved","closed","completed","active","verified","matched","reconciled","promoted","confirmed in pms"].some(x => normalized.includes(x));
  const bad = ["rejected","failed","exception","blocked","urgent","overdue"].some(x => normalized.includes(x));
  const warning = ["waiting","pending","review","partial","unverified","due"].some(x => normalized.includes(x));
  const cls = good
    ? "border-emerald-200 bg-emerald-50 text-emerald-800"
    : bad
      ? "border-rose-200 bg-rose-50 text-rose-800"
      : warning
        ? "border-amber-200 bg-amber-50 text-amber-900"
        : "border-slate-200 bg-slate-50 text-slate-700";
  return <span className={`inline-flex rounded-md border px-2.5 py-1 text-xs font-semibold ${cls}`}>{text}</span>;
}
