export function MetricCard({ label, value, note }: { label: string; value: string; note: string }) {
  return <article className="rounded-2xl border border-stone-200 bg-white p-5"><p className="text-sm text-stone-500">{label}</p><p className="mt-2 text-3xl font-semibold text-[#4a1f3e]">{value}</p><p className="mt-2 text-xs text-stone-500">{note}</p></article>;
}
