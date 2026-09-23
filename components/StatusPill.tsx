export function StatusPill({ value }: { value: string | null | undefined }) {
  const text = value || "unknown";
  const normalized = text.toLowerCase().replaceAll("_", " ");
  const good = ["paid","resolved","closed","completed","active","verified","matched","reconciled","promoted","confirmed in pms"].some(x => normalized.includes(x));
  const bad = ["rejected","failed","exception","blocked","urgent","overdue"].some(x => normalized.includes(x));
  const cls = good ? "bg-emerald-50 text-emerald-800 border-emerald-200" : bad ? "bg-rose-50 text-rose-800 border-rose-200" : "bg-stone-50 text-stone-700 border-stone-200";
  return <span className={`inline-flex rounded-full border px-2.5 py-1 text-xs font-medium ${cls}`}>{text}</span>;
}
