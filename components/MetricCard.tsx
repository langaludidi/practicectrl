export function MetricCard({ label, value, note }: { label: string; value: string; note: string }) {
  return <article className="rounded-lg border border-[#dce3ea] bg-white p-5">
    <p className="text-sm font-medium text-[#526276]">{label}</p>
    <p className="mt-2 text-3xl font-semibold tracking-tight text-[#051a39]">{value}</p>
    <p className="mt-2 text-xs leading-5 text-[#64748b]">{note}</p>
  </article>;
}
