export function EmptyState({ title, body }: { title: string; body: string }) {
  return <div className="rounded-lg border border-dashed border-[#cbd5e1] bg-white p-8 text-center">
    <h3 className="font-semibold text-[#051a39]">{title}</h3>
    <p className="mx-auto mt-2 max-w-xl text-sm leading-6 text-[#526276]">{body}</p>
  </div>;
}
