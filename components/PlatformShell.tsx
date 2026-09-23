import Link from "next/link";
import type { PlatformRole } from "@/lib/auth/server";

export function PlatformShell({ children, role, email }: { children: React.ReactNode; role: PlatformRole; email: string | null }) {
  return <div className="min-h-screen lg:grid lg:grid-cols-[250px_1fr]">
    <aside className="border-b border-stone-200 bg-stone-950 p-5 text-white lg:min-h-screen lg:border-b-0 lg:border-r">
      <p className="text-xs font-bold tracking-[.2em] text-[#f28a76]">PRACTICECTRL PLATFORM</p>
      <h1 className="mt-2 text-xl font-semibold">Tenant control plane</h1>
      <p className="mt-2 text-xs leading-5 text-white/60">Global governance is separated from practice-level administration.</p>
      <nav className="mt-7 grid gap-1">
        <Link href="/platform/tenants" className="rounded-xl px-3 py-2.5 text-sm text-white/85 hover:bg-white/10">Tenants</Link>
        <Link href="/platform/sources" className="rounded-xl px-3 py-2.5 text-sm text-white/85 hover:bg-white/10">Global Source Register</Link>
        <Link href="/select-practice" className="rounded-xl px-3 py-2.5 text-sm text-white/85 hover:bg-white/10">Practice workspace</Link>
      </nav>
      <div className="mt-8 border-t border-white/15 pt-4 text-xs text-white/60"><p>{role.replaceAll("_"," ")}</p><p className="truncate">{email ?? "Platform operator"}</p></div>
    </aside>
    <main className="min-w-0"><header className="border-b border-stone-200 bg-white px-5 py-4 lg:px-8"><p className="text-xs font-semibold uppercase tracking-[.14em] text-stone-500">Platform operations</p><p className="text-sm text-stone-700">Tenant provisioning and global data governance only</p></header><div className="p-5 lg:p-8">{children}</div></main>
  </div>;
}
