export function SectionHeader({ title, body, action }: { title: string; body?: string; action?: React.ReactNode }) {
  return <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
    <div><h2 className="text-3xl font-semibold text-[#4a1f3e]">{title}</h2>{body ? <p className="mt-1 max-w-4xl text-stone-600">{body}</p> : null}</div>
    {action}
  </div>;
}
