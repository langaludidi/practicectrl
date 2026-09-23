import Link from "next/link";
import type { PlatformRole } from "@/lib/auth/server";
import { canViewClinicalRecords, canViewEconomics, canViewRecovery, type StaffRole } from "@/lib/auth/roles";

function navForRole(role: StaffRole): Array<readonly [string,string]> {
  const nav:Array<readonly [string,string]> = [
    ["Dashboard","/dashboard"], ["Diary","/appointments"], ["Requests","/requests"], ["Patient Intake","/intake"], ["Patients","/patients"], ["Documents & Forms","/documents"], ["Authorisations","/authorisations"], ["Communications","/communications"],
    ["Clinical coding","/coding"], ["Operations","/operations"], ["Command Centre","/analytics"], ["Audit","/audit"]
  ];
  if (canViewClinicalRecords(role)) nav.splice(3,0,["Clinical Records","/clinical"],["Pathology","/pathology"],["Medicines","/medicines"]);
  if (["billing","finance","practice_manager","system_admin","auditor"].includes(role)) {
    nav.splice(5,0,["Billing","/billing"],["Payer Contracts","/contracts"],["Claims & ERA","/claims"],["Revenue Integrity","/integrity"],["Revenue control","/revenue"]);
  }
  if (canViewEconomics(role)) nav.splice(nav.findIndex(x=>x[1]==="/analytics"),0,["Practice Economics","/economics"]);
  if (canViewRecovery(role)) nav.splice(nav.findIndex(x=>x[1]==="/analytics"),0,["Recovery Workbench","/recovery"]);
  if (["billing","finance","practice_manager","system_admin","auditor"].includes(role)) nav.push(["VeriClaim imports","/admin/imports"]);
  if (["practice_manager","system_admin","auditor"].includes(role)) nav.push(["Staff & Access","/admin/staff"],["Integration Hub","/admin/integrations"],["Release Readiness","/admin/readiness"]);
  if (role === "system_admin") nav.push(["Modules","/admin/modules"],["AI & Voice","/admin/assist"],["Source Register","/admin/sources"]);
  return nav;
}

export function AppShell({
  children, role, email, practiceName, tenantSlug, membershipCount, platformRole,
}: {
  children: React.ReactNode;
  role: StaffRole;
  email: string | null;
  practiceName: string;
  tenantSlug: string;
  membershipCount: number;
  platformRole: PlatformRole | null;
}) {
  const nav=navForRole(role);
  return <div className="min-h-screen lg:grid lg:grid-cols-[260px_1fr]">
    <aside className="border-b border-stone-200 bg-[#3f1935] p-5 text-white lg:min-h-screen lg:border-b-0 lg:border-r">
      <div className="mb-7">
        <p className="text-xs font-bold tracking-[.2em] text-[#f28a76]">PRACTICECTRL</p>
        <h1 className="mt-2 text-xl font-semibold">{practiceName}</h1>
        <p className="mt-1 text-xs text-white/55">{tenantSlug}</p>
        <p className="mt-2 text-xs text-white/65">Clinical Operations. Coding Intelligence. Revenue Integrity.</p>
        {membershipCount > 1 ? <Link href="/select-practice" className="mt-3 inline-block rounded-lg border border-white/20 px-2.5 py-1.5 text-xs font-medium text-white/85 hover:bg-white/10">Switch practice</Link> : null}
      </div>
      <nav className="grid gap-1">{nav.map(([label,href]) => <Link key={href} href={href} className="rounded-xl px-3 py-2.5 text-sm text-white/85 hover:bg-white/10 hover:text-white">{label}</Link>)}</nav>
      <div className="mt-8 border-t border-white/15 pt-4 text-xs text-white/65">
        <p>{role.replaceAll("_"," ")}</p>
        <p className="truncate">{email ?? "Authenticated user"}</p>
        <div className="mt-3 flex flex-wrap gap-3">
          <Link href="/invitations" className="text-white/80 underline underline-offset-4">Invitations</Link>
          {platformRole ? <Link href="/platform/tenants" className="text-white/80 underline underline-offset-4">Platform console</Link> : null}
        </div>
      </div>
    </aside>
    <main className="min-w-0"><header className="flex flex-wrap items-center justify-between gap-3 border-b border-stone-200 bg-white px-5 py-4 lg:px-8"><div><p className="text-xs font-semibold uppercase tracking-[.14em] text-stone-500">{practiceName}</p><p className="text-sm text-stone-700">PracticeCtrl diary, clinical and revenue workflows share one governed patient journey</p></div><span className="rounded-full bg-amber-50 px-3 py-1 text-xs font-medium text-amber-800">Controlled staging</span></header><div className="p-5 lg:p-8">{children}</div></main>
  </div>;
}
