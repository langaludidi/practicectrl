"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import type { StaffRole } from "@/lib/auth/roles";
import { reportsForRole } from "@/lib/reports/catalogue";

const FAVORITES_KEY = "practicectrl.reports.favorites";

function Star({ active }: { active: boolean }) {
  return <svg viewBox="0 0 24 24" className="h-4 w-4" fill={active ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
    <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9L12 3Z"/>
  </svg>;
}

export function ReportsWorkspace({ role }: { role: StaffRole }) {
  const allReports = useMemo(() => reportsForRole(role), [role]);
  const categories = useMemo(() => [...new Set(allReports.map(report => report.category))], [allReports]);
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("All");
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [favorites, setFavorites] = useState<string[]>([]);

  useEffect(() => {
    try {
      const parsed = JSON.parse(window.localStorage.getItem(FAVORITES_KEY) || "[]");
      if (Array.isArray(parsed)) setFavorites(parsed.filter(value => typeof value === "string"));
    } catch {
      setFavorites([]);
    }
  }, []);

  function toggleFavorite(id: string) {
    setFavorites(current => {
      const next = current.includes(id) ? current.filter(value => value !== id) : [...current, id];
      window.localStorage.setItem(FAVORITES_KEY, JSON.stringify(next));
      return next;
    });
  }

  const filtered = allReports.filter(report => {
    if (favoritesOnly && !favorites.includes(report.id)) return false;
    if (category !== "All" && report.category !== category) return false;
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return [report.category, report.legacyName, report.practiceCtrlName, report.description, ...(report.keywords || [])]
      .join(" ")
      .toLowerCase()
      .includes(q);
  });

  const grouped = categories
    .map(name => ({ name, reports: filtered.filter(report => report.category === name) }))
    .filter(group => group.reports.length);

  return <div className="space-y-5">
    <section className="border border-[#dce3ea] bg-white">
      <div className="grid gap-4 p-4 lg:grid-cols-[minmax(0,1fr)_220px_auto] lg:items-end">
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[#334155]">Find a report or business question</span>
          <input
            value={query}
            onChange={event => setQuery(event.target.value)}
            placeholder="Search invoice, ageing, ICD-10, pathology, referring provider…"
            className="h-11 w-full border border-[#cfd8e3] bg-white px-3 text-sm text-[#12243b] outline-none focus:border-[#236cfb]"
          />
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-semibold text-[#334155]">Report family</span>
          <select
            value={category}
            onChange={event => setCategory(event.target.value)}
            className="h-11 w-full border border-[#cfd8e3] bg-white px-3 text-sm text-[#12243b] outline-none focus:border-[#236cfb]"
          >
            <option>All</option>
            {categories.map(name => <option key={name}>{name}</option>)}
          </select>
        </label>
        <button
          type="button"
          onClick={() => setFavoritesOnly(value => !value)}
          className={`inline-flex h-11 items-center justify-center gap-2 border px-4 text-sm font-semibold ${favoritesOnly ? "border-[#029ea1] bg-[#e9f8f8] text-[#056b6e]" : "border-[#cfd8e3] bg-white text-[#334155] hover:border-[#029ea1]"}`}
        >
          <Star active={favoritesOnly} />
          Favourite reports
        </button>
      </div>
      <div className="border-t border-[#e5eaf0] bg-[#f8fafc] px-4 py-3 text-sm text-[#526276]">
        <strong className="text-[#051a39]">{allReports.length} mapped report views</strong> are available for your role. PracticeCtrl preserves the business information from the legacy reports, but presents it through live workspaces, filters, drill-downs, governance views and audit trails rather than recreating the old report screens.
      </div>
    </section>

    {grouped.length ? grouped.map(group => <section key={group.name} className="border border-[#dce3ea] bg-white">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[#dce3ea] px-4 py-3">
        <div>
          <h2 className="text-base font-semibold text-[#051a39]">{group.name}</h2>
          <p className="mt-0.5 text-xs text-[#64748b]">{group.reports.length} available {group.reports.length === 1 ? "view" : "views"}</p>
        </div>
      </div>
      <div className="divide-y divide-[#e5eaf0]">
        {group.reports.map(report => {
          const favourite = favorites.includes(report.id);
          return <div key={report.id} className="grid gap-3 px-4 py-4 lg:grid-cols-[minmax(240px,0.95fr)_minmax(320px,1.35fr)_150px_112px] lg:items-center">
            <div className="min-w-0">
              <p className="text-sm font-semibold text-[#12243b]">{report.legacyName}</p>
              <p className="mt-1 text-xs font-medium text-[#067c80]">PracticeCtrl: {report.practiceCtrlName}</p>
            </div>
            <p className="text-sm leading-6 text-[#526276]">{report.description}</p>
            <span className="w-fit border border-[#dce3ea] bg-[#f8fafc] px-2.5 py-1 text-xs font-semibold text-[#475569]">{report.surface}</span>
            <div className="flex items-center justify-end gap-1">
              <button
                type="button"
                onClick={() => toggleFavorite(report.id)}
                className={`inline-flex h-9 w-9 items-center justify-center border ${favourite ? "border-[#029ea1] text-[#029ea1]" : "border-[#dce3ea] text-[#64748b] hover:border-[#029ea1] hover:text-[#029ea1]"}`}
                aria-label={favourite ? `Remove ${report.legacyName} from favourites` : `Add ${report.legacyName} to favourites`}
                title={favourite ? "Remove from favourites" : "Add to favourites"}
              >
                <Star active={favourite} />
              </button>
              <Link href={report.href} className="inline-flex h-9 items-center border border-[#067c80] bg-[#067c80] px-3 text-xs font-semibold text-white hover:bg-[#056b6e]">
                Open
              </Link>
            </div>
          </div>;
        })}
      </div>
    </section>) : <section className="border border-[#dce3ea] bg-white p-8 text-center">
      <h2 className="text-base font-semibold text-[#051a39]">No reports match those filters</h2>
      <p className="mt-2 text-sm text-[#64748b]">Clear the search, choose another family, or turn off Favourite reports.</p>
    </section>}
  </div>;
}
