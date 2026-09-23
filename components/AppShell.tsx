"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { canViewClinicalRecords, canViewEconomics, canViewRecovery, type StaffRole } from "@/lib/auth/roles";

type SidebarMode = "expanded" | "collapsed" | "hidden";
type NavItem = { label: string; href: string; icon: "today" | "patient" | "work" | "clinical" | "billing" | "claims" | "revenue" | "report" | "admin" };
type NavSection = { label: string; items: NavItem[] };

function navForRole(role: StaffRole): NavSection[] {
  const sections: NavSection[] = [
    {
      label: "Workspace",
      items: [
        { label: "Today", href: "/dashboard", icon: "today" },
        { label: "Patients", href: "/patients", icon: "patient" },
        { label: "Operations", href: "/operations", icon: "work" },
        { label: "Appointments", href: "/appointments", icon: "work" },
        { label: "Requests", href: "/requests", icon: "work" },
        { label: "Patient intake", href: "/intake", icon: "patient" },
      ],
    },
    {
      label: "Clinical & Code10",
      items: [
        { label: "Clinical & Code10", href: "/coding", icon: "clinical" },
        { label: "Documents & forms", href: "/documents", icon: "clinical" },
        { label: "Authorisations", href: "/authorisations", icon: "clinical" },
      ],
    },
    {
      label: "Practice",
      items: [
        { label: "Communications", href: "/communications", icon: "work" },
        { label: "Reports", href: "/analytics", icon: "report" },
        { label: "Audit trail", href: "/audit", icon: "report" },
      ],
    },
  ];

  if (canViewClinicalRecords(role)) {
    sections[1].items.splice(
      1,
      0,
      { label: "Clinical records", href: "/clinical", icon: "clinical" },
      { label: "Pathology", href: "/pathology", icon: "clinical" },
      { label: "Medicines", href: "/medicines", icon: "clinical" },
    );
  }

  if (["billing", "finance", "practice_manager", "system_admin", "auditor"].includes(role)) {
    const revenue: NavItem[] = [
      { label: "Billing", href: "/billing", icon: "billing" },
      { label: "Claims & ERA", href: "/claims", icon: "claims" },
      { label: "Revenue integrity", href: "/integrity", icon: "revenue" },
      { label: "Revenue control", href: "/revenue", icon: "revenue" },
      { label: "Payer contracts", href: "/contracts", icon: "billing" },
    ];
    if (canViewEconomics(role)) revenue.push({ label: "Practice economics", href: "/economics", icon: "report" });
    if (canViewRecovery(role)) revenue.push({ label: "Recovery workbench", href: "/recovery", icon: "revenue" });
    sections.splice(2, 0, { label: "Revenue", items: revenue });
  } else if (canViewEconomics(role)) {
    sections.splice(2, 0, {
      label: "Economics",
      items: [{ label: "Practice economics", href: "/economics", icon: "report" }],
    });
  }

  const adminItems: NavItem[] = [];
  if (["billing", "finance", "practice_manager", "system_admin", "auditor"].includes(role)) {
    adminItems.push({ label: "VeriClaim imports", href: "/admin/imports", icon: "admin" });
  }
  if (["practice_manager", "system_admin", "auditor"].includes(role)) {
    adminItems.push(
      { label: "Staff & access", href: "/admin/staff", icon: "admin" },
      { label: "Integration hub", href: "/admin/integrations", icon: "admin" },
      { label: "Release readiness", href: "/admin/readiness", icon: "admin" },
    );
  }
  if (role === "system_admin") {
    adminItems.push(
      { label: "Modules", href: "/admin/modules", icon: "admin" },
      { label: "AI & voice governance", href: "/admin/assist", icon: "admin" },
      { label: "Source register", href: "/admin/sources", icon: "admin" },
    );
  }
  if (adminItems.length) sections.push({ label: "Administration", items: adminItems });

  return sections;
}

function NavGlyph({ icon }: { icon: NavItem["icon"] }) {
  const common = "h-5 w-5 shrink-0";
  if (icon === "today") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><path d="M3.5 10.5 12 3l8.5 7.5"/><path d="M5.5 9.5V21h13V9.5M9.5 21v-6h5v6"/></svg>;
  if (icon === "patient") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><circle cx="12" cy="8" r="3.5"/><path d="M5 20c.8-4 3.2-6 7-6s6.2 2 7 6"/></svg>;
  if (icon === "clinical") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><path d="M9 4h6v5h5v6h-5v5H9v-5H4V9h5V4Z"/></svg>;
  if (icon === "billing") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><path d="M6 3h12v18H6z"/><path d="M9 8h6M9 12h6M9 16h4"/></svg>;
  if (icon === "claims") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><path d="M6 3h9l3 3v15H6z"/><path d="m9 14 2 2 4-5"/></svg>;
  if (icon === "revenue") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><path d="M4 20V8M10 20V4M16 20v-7M22 20H2"/></svg>;
  if (icon === "report") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><path d="M4 20V5h16v15H4Z"/><path d="M8 15v2M12 11v6M16 8v9"/></svg>;
  if (icon === "admin") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M18.7 5.3l-2.1 2.1M7.4 16.6l-2.1 2.1"/></svg>;
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={common} aria-hidden="true"><path d="M4 6h16M4 12h10M4 18h13"/><circle cx="18" cy="12" r="2"/></svg>;
}

function ShellControlIcon({ type }: { type: "menu" | "collapse" | "expand" | "hide" }) {
  if (type === "menu") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-5 w-5" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h16"/></svg>;
  if (type === "collapse") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-5 w-5" aria-hidden="true"><path d="m14 6-6 6 6 6"/></svg>;
  if (type === "expand") return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-5 w-5" aria-hidden="true"><path d="m10 6 6 6-6 6"/></svg>;
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-5 w-5" aria-hidden="true"><path d="M5 5l14 14M19 5 5 19"/></svg>;
}

export function AppShell({
  children,
  role,
  email,
  practiceName,
  tenantSlug,
  membershipCount,
  platformRole,
}: {
  children: ReactNode;
  role: StaffRole;
  email: string | null;
  practiceName: string;
  tenantSlug: string;
  membershipCount: number;
  platformRole: string | null;
}) {
  const pathname = usePathname();
  const sections = navForRole(role);
  const [sidebarMode, setSidebarMode] = useState<SidebarMode>("expanded");
  const [sidebarPreferenceLoaded, setSidebarPreferenceLoaded] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    const saved = window.localStorage.getItem("practicectrl.sidebar.mode");
    if (saved === "expanded" || saved === "collapsed" || saved === "hidden") setSidebarMode(saved);
    setSidebarPreferenceLoaded(true);
  }, []);

  useEffect(() => {
    if (sidebarPreferenceLoaded) window.localStorage.setItem("practicectrl.sidebar.mode", sidebarMode);
  }, [sidebarMode, sidebarPreferenceLoaded]);

  useEffect(() => setMobileOpen(false), [pathname]);

  const desktopWidth = sidebarMode === "expanded" ? "lg:w-[280px]" : sidebarMode === "collapsed" ? "lg:w-[76px]" : "lg:w-0 lg:border-r-0";
  const innerWidth = sidebarMode === "collapsed" ? "lg:w-[76px]" : "lg:w-[280px]";
  const showLabels = sidebarMode === "expanded";

  return <div className="min-h-screen bg-[#f6f8fa] lg:flex">
    {mobileOpen ? <button aria-label="Close navigation" className="fixed inset-0 z-40 bg-[#051a39]/45 lg:hidden" onClick={() => setMobileOpen(false)} /> : null}

    <aside className={`fixed inset-y-0 left-0 z-50 w-[280px] overflow-hidden border-r border-white/10 bg-[#051a39] text-white transition-[width,transform] duration-200 lg:sticky lg:top-0 lg:z-40 lg:h-screen lg:translate-x-0 ${desktopWidth} ${mobileOpen ? "translate-x-0" : "-translate-x-full"}`}>
      <div className={`flex h-full w-[280px] flex-col overflow-y-auto transition-[width] duration-200 ${innerWidth}`}>
        <div className="border-b border-white/10 p-3">
          <div className={`flex min-h-14 items-center rounded-lg bg-white ${showLabels ? "justify-start px-3" : "lg:justify-center lg:px-2"}`}>
            {showLabels ? (
              <Image src="/brand/practicectrl-primary-logo.png" alt="PracticeCtrl" width={2048} height={682} priority className="h-9 w-auto max-w-full object-contain" />
            ) : (
              <div className="relative h-10 w-10 overflow-hidden" title="PracticeCtrl">
                <Image src="/brand/practicectrl-primary-logo.png" alt="PracticeCtrl" width={2048} height={682} priority className="h-10 w-auto max-w-none object-contain object-left" />
              </div>
            )}
          </div>
          {showLabels ? <div className="px-2 pb-1 pt-4">
            <p className="text-[11px] font-semibold uppercase tracking-[.14em] text-white/55">Active practice</p>
            <p className="mt-1 truncate text-sm font-semibold text-white">{practiceName}</p>
            <p className="mt-0.5 truncate text-xs text-white/55">{tenantSlug}</p>
            {membershipCount > 1 ? <Link href="/select-practice" className="mt-3 inline-flex items-center text-xs font-semibold text-[#64d9d8] hover:text-white">Switch practice →</Link> : null}
          </div> : null}
        </div>

        <nav aria-label="Practice navigation" className="flex-1 space-y-5 px-2 py-4">
          {sections.map(section => <div key={section.label}>
            {showLabels ? <p className="mb-1.5 px-2 text-[10px] font-semibold uppercase tracking-[.15em] text-white/40">{section.label}</p> : null}
            <div className="grid gap-1">
              {section.items.map(item => {
                const active = pathname === item.href || (item.href !== "/dashboard" && pathname.startsWith(item.href + "/"));
                return <Link
                  key={item.href}
                  href={item.href}
                  title={!showLabels ? item.label : undefined}
                  aria-current={active ? "page" : undefined}
                  className={`group flex min-h-10 items-center gap-3 rounded-md border-l-2 px-2.5 py-2 text-sm transition-colors ${showLabels ? "" : "lg:justify-center lg:px-2"} ${active ? "border-[#22b8b8] bg-white/10 font-semibold text-white" : "border-transparent text-white/70 hover:bg-white/10 hover:text-white"}`}
                >
                  <NavGlyph icon={item.icon} />
                  <span className={showLabels ? "truncate" : "lg:sr-only"}>{item.label}</span>
                </Link>;
              })}
            </div>
          </div>)}
        </nav>

        <div className="border-t border-white/10 p-3">
          {showLabels ? <div className="mb-3 px-2 text-xs leading-5 text-white/60">
            <p className="font-semibold capitalize text-white/85">{role.replaceAll("_", " ")}</p>
            <p className="truncate">{email ?? "Authenticated user"}</p>
            <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1">
              <Link href="/invitations" className="font-medium text-[#64d9d8] hover:text-white">Invitations</Link>
              {platformRole ? <Link href="/platform/tenants" className="font-medium text-[#64d9d8] hover:text-white">Platform console</Link> : null}
            </div>
          </div> : null}
          <div className={`flex gap-1 ${showLabels ? "justify-between" : "lg:flex-col"}`}>
            <button
              type="button"
              onClick={() => setSidebarMode(sidebarMode === "collapsed" ? "expanded" : "collapsed")}
              className="hidden min-h-10 items-center justify-center gap-2 rounded-md border border-white/15 px-2.5 text-xs font-semibold text-white/75 hover:bg-white/10 hover:text-white lg:flex"
              title={sidebarMode === "collapsed" ? "Expand navigation" : "Collapse navigation"}
            >
              <ShellControlIcon type={sidebarMode === "collapsed" ? "expand" : "collapse"} />
              {showLabels ? <span>Collapse</span> : null}
            </button>
            <button
              type="button"
              onClick={() => setSidebarMode("hidden")}
              className="hidden min-h-10 items-center justify-center gap-2 rounded-md border border-white/15 px-2.5 text-xs font-semibold text-white/75 hover:bg-white/10 hover:text-white lg:flex"
              title="Hide navigation for full-width work"
            >
              <ShellControlIcon type="hide" />
              {showLabels ? <span>Hide</span> : null}
            </button>
          </div>
        </div>
      </div>
    </aside>

    <main className="min-w-0 flex-1">
      <header className="sticky top-0 z-30 border-b border-[#dce3ea] bg-white">
        <div className="flex min-h-16 items-center gap-3 px-4 sm:px-6 lg:px-8">
          <button type="button" onClick={() => setMobileOpen(true)} className="inline-flex h-10 w-10 items-center justify-center rounded-md border border-[#dce3ea] text-[#051a39] lg:hidden" aria-label="Open navigation"><ShellControlIcon type="menu" /></button>
          {sidebarMode === "hidden" ? <button type="button" onClick={() => setSidebarMode("expanded")} className="hidden h-10 items-center gap-2 rounded-md border border-[#dce3ea] bg-white px-3 text-sm font-semibold text-[#051a39] hover:bg-[#f6f8fa] lg:inline-flex"><ShellControlIcon type="expand" />Navigation</button> : null}

          <div className="min-w-0">
            <p className="text-[10px] font-semibold uppercase tracking-[.14em] text-[#64748b]">Active practice</p>
            <p className="truncate text-sm font-semibold text-[#051a39]">{practiceName}</p>
          </div>

          <Link href="/patients" className="ml-auto hidden min-w-0 max-w-md flex-1 items-center gap-2 rounded-md border border-[#dce3ea] bg-[#f8fafc] px-3 py-2 text-sm text-[#5b6b7d] hover:border-[#029ea1] hover:bg-white md:flex" aria-label="Search patients and records">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-4 w-4 shrink-0" aria-hidden="true"><circle cx="11" cy="11" r="6"/><path d="m16 16 4 4"/></svg>
            <span className="truncate">Search patients and records</span>
          </Link>

          <Link href="/dashboard#attention" className="hidden rounded-md px-3 py-2 text-sm font-medium text-[#334155] hover:bg-[#f1f5f9] sm:inline-flex">Attention</Link>
          <span className="hidden rounded-md border border-amber-200 bg-amber-50 px-2.5 py-1.5 text-xs font-semibold text-amber-900 xl:inline-flex">Controlled staging</span>
          <div className="hidden border-l border-[#dce3ea] pl-3 text-right sm:block">
            <p className="text-xs font-semibold capitalize text-[#051a39]">{role.replaceAll("_", " ")}</p>
            <p className="max-w-[180px] truncate text-[11px] text-[#64748b]">{email ?? "Authenticated user"}</p>
          </div>
        </div>
      </header>

      <div className="mx-auto w-full max-w-[1800px] px-4 py-6 sm:px-6 lg:px-8 lg:py-8 xl:px-10">{children}</div>
    </main>
  </div>;
}
