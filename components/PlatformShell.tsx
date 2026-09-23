import Image from "next/image";
import Link from "next/link";
import type { PlatformRole } from "@/lib/auth/server";

export function PlatformShell({ children, role, email }: { children: React.ReactNode; role: PlatformRole; email: string | null }) {
  return <div className="min-h-screen bg-[#f6f8fa] lg:grid lg:grid-cols-[260px_1fr]">
    <aside className="border-b border-white/10 bg-[#051a39] p-4 text-white lg:min-h-screen lg:border-b-0 lg:border-r">
      <div className="rounded-lg bg-white px-3 py-3">
        <Image src="/brand/practicectrl-primary-logo.png" alt="PracticeCtrl" width={2048} height={682} className="h-9 w-auto max-w-full object-contain" />
      </div>
      <p className="mt-5 text-[10px] font-semibold uppercase tracking-[.15em] text-white/45">Platform operations</p>
      <h1 className="mt-1 text-lg font-semibold text-white">Tenant control plane</h1>
      <p className="mt-2 text-xs leading-5 text-white/60">Global governance remains separate from practice-level administration.</p>
      <nav className="mt-6 grid gap-1">
        <Link href="/platform/tenants" className="rounded-md border-l-2 border-transparent px-3 py-2.5 text-sm text-white/80 hover:bg-white/10 hover:text-white">Tenants</Link>
        <Link href="/platform/sources" className="rounded-md border-l-2 border-transparent px-3 py-2.5 text-sm text-white/80 hover:bg-white/10 hover:text-white">Global source register</Link>
        <Link href="/select-practice" className="rounded-md border-l-2 border-transparent px-3 py-2.5 text-sm text-white/80 hover:bg-white/10 hover:text-white">Practice workspace</Link>
      </nav>
      <div className="mt-8 border-t border-white/10 pt-4 text-xs leading-5 text-white/60"><p className="font-semibold capitalize text-white/80">{role.replaceAll("_", " ")}</p><p className="truncate">{email ?? "Platform operator"}</p></div>
    </aside>
    <main className="min-w-0">
      <header className="border-b border-[#dce3ea] bg-white px-5 py-4 lg:px-8"><p className="text-[10px] font-semibold uppercase tracking-[.14em] text-[#64748b]">Platform operations</p><p className="mt-0.5 text-sm text-[#526276]">Tenant provisioning and global data governance only</p></header>
      <div className="p-5 lg:p-8">{children}</div>
    </main>
  </div>;
}
