export function SectionHeader({ title, body, action }: { title: string; body?: string; action?: React.ReactNode }) {
  return <header className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
    <div className="min-w-0">
      <h1 className="text-2xl font-semibold tracking-tight text-[#051a39] sm:text-[28px]">{title}</h1>
      {body ? <p className="mt-1.5 max-w-4xl text-sm leading-6 text-[#526276] sm:text-[15px]">{body}</p> : null}
    </div>
    {action ? <div className="shrink-0">{action}</div> : null}
  </header>;
}
