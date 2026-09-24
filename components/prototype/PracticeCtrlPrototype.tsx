"use client";

import { useEffect, useMemo, useState } from "react";

type ScreenId = "command" | "patient" | "operations" | "billing" | "revenue" | "code10" | "states";
type Role = "owner" | "claims" | "reception" | "practitioner";
type DrawerItem = {
  title: string;
  subtitle: string;
  status: string;
  why: string;
  evidence: string[];
  action: string;
} | null;

type WorkRow = {
  id: string;
  task: string;
  patient: string;
  type: string;
  owner: string;
  due: string;
  status: "Overdue" | "Today" | "Blocked" | "Open";
};

const NAV_GROUPS: { label: string; items: { id: ScreenId; label: string; glyph: string }[] }[] = [
  { label: "CARE", items: [
    { id: "patient", label: "Patients", glyph: "P" },
  ]},
  { label: "OPERATIONS", items: [
    { id: "operations", label: "Operations", glyph: "O" },
  ]},
  { label: "REVENUE", items: [
    { id: "billing", label: "Billing", glyph: "B" },
    { id: "revenue", label: "Revenue Control", glyph: "R" },
  ]},
  { label: "INTELLIGENCE", items: [
    { id: "code10", label: "Code10", glyph: "10" },
  ]},
  { label: "SYSTEM", items: [
    { id: "states", label: "UX States", glyph: "S" },
  ]},
];

const WORK_ROWS: WorkRow[] = [
  { id: "W-1204", task: "Verify authorisation", patient: "Nomsa Moyo", type: "Claim blocker", owner: "Amanda", due: "Today", status: "Blocked" },
  { id: "W-1203", task: "Resolve tariff variance", patient: "Thando Jacobs", type: "Revenue", owner: "Lerato", due: "09:30", status: "Overdue" },
  { id: "W-1198", task: "Complete membership check", patient: "Siyanda Dube", type: "Eligibility", owner: "Amanda", due: "Today", status: "Today" },
  { id: "W-1191", task: "Review rejected claim", patient: "Nandi Zulu", type: "Claim", owner: "Unassigned", due: "Yesterday", status: "Overdue" },
  { id: "W-1188", task: "Confirm coding finding", patient: "Peter Adams", type: "Code10", owner: "Dr Tini", due: "Tomorrow", status: "Open" },
];

const SEARCH_ITEMS = [
  { kind: "Patient", title: "Nomsa Moyo", meta: "PC-001284 · Discovery Health", screen: "patient" as ScreenId },
  { kind: "Invoice", title: "INV-2026-00421 · Nomsa Moyo", meta: "Blocked · R1,240.00", screen: "billing" as ScreenId },
  { kind: "Claim", title: "CLM-260924-04", meta: "Nomsa Moyo · 2 blocking issues", screen: "billing" as ScreenId },
  { kind: "Work item", title: "Authorisation follow-up · Nomsa Moyo", meta: "Due today · Amanda", screen: "operations" as ScreenId },
];

function cx(...values: Array<string | false | null | undefined>) {
  return values.filter(Boolean).join(" ");
}

function StatusBadge({ value }: { value: string }) {
  const normalized = value.toLowerCase();
  const tone = normalized.includes("block") || normalized.includes("overdue")
    ? "border-rose-200 bg-rose-50 text-rose-800"
    : normalized.includes("review") || normalized.includes("today") || normalized.includes("warning")
      ? "border-amber-200 bg-amber-50 text-amber-800"
      : normalized.includes("ready") || normalized.includes("verified") || normalized.includes("resolved")
        ? "border-emerald-200 bg-emerald-50 text-emerald-800"
        : "border-slate-200 bg-slate-50 text-slate-700";
  const icon = normalized.includes("block") || normalized.includes("overdue") ? "⊘" : normalized.includes("review") || normalized.includes("today") || normalized.includes("warning") ? "⚠" : normalized.includes("ready") || normalized.includes("verified") || normalized.includes("resolved") ? "✓" : "•";
  return <span className={cx("inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-semibold", tone)}><span aria-hidden="true">{icon}</span>{value}</span>;
}

function SectionTitle({ title, note, action }: { title: string; note?: string; action?: string }) {
  return <div className="flex flex-wrap items-start justify-between gap-4">
    <div>
      <h2 className="text-xl font-semibold text-[var(--pc-navy)]">{title}</h2>
      {note ? <p className="mt-1 text-sm text-slate-500">{note}</p> : null}
    </div>
    {action ? <button className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-50">{action}</button> : null}
  </div>;
}

function Metric({ label, value, note, attention, onClick }: { label: string; value: string; note: string; attention?: boolean; onClick?: () => void }) {
  const content = <div className="min-h-[126px] rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm">
    <p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">{label}</p>
    <p className={cx("mt-3 text-2xl font-semibold", attention ? "text-rose-700" : "text-[var(--pc-navy)]")}>{value}</p>
    <p className="mt-2 text-sm text-slate-500">{note}</p>
  </div>;
  if (!onClick) return content;
  return <button className="block w-full rounded-xl text-left transition hover:-translate-y-0.5 hover:shadow-md" onClick={onClick}>{content}</button>;
}

function Drawer({ item, onClose }: { item: DrawerItem; onClose: () => void }) {
  if (!item) return null;
  return <>
    <button aria-label="Close inspection drawer" className="fixed inset-0 z-40 bg-[#051a39]/20" onClick={onClose} />
    <aside className="fixed inset-y-0 right-0 z-50 w-full max-w-[470px] overflow-y-auto border-l border-slate-200 bg-white shadow-2xl">
      <div className="sticky top-0 flex items-start justify-between gap-4 border-b border-slate-200 bg-white p-5">
        <div><p className="text-xs font-semibold uppercase tracking-[0.12em] text-slate-500">Inspect</p><h2 className="mt-1 text-xl font-semibold">{item.title}</h2><p className="mt-1 text-sm text-slate-500">{item.subtitle}</p></div>
        <button onClick={onClose} className="rounded-lg border border-slate-200 px-3 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">Close</button>
      </div>
      <div className="space-y-6 p-5">
        <StatusBadge value={item.status} />
        <div><h3 className="text-sm font-semibold text-[var(--pc-navy)]">Why this needs attention</h3><p className="mt-2 text-sm leading-6 text-slate-600">{item.why}</p></div>
        <div><h3 className="text-sm font-semibold text-[var(--pc-navy)]">Evidence</h3><div className="mt-3 space-y-2">{item.evidence.map((line) => <div key={line} className="flex items-start gap-2 rounded-lg bg-slate-50 px-3 py-2 text-sm text-slate-600"><span className="mt-0.5 text-[var(--pc-teal-action)]">✓</span><span>{line}</span></div>)}</div></div>
        <button className="w-full rounded-lg bg-[var(--pc-teal-action)] px-4 py-3 text-sm font-semibold text-white hover:opacity-95">{item.action}</button>
        <button className="w-full rounded-lg border border-slate-200 px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-slate-50">View full record →</button>
        <div className="border-t border-slate-200 pt-5"><p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Last changed</p><p className="mt-2 text-sm font-semibold text-slate-700">Amanda M. · 24 Sep 2026 · 14:02</p><p className="mt-1 text-sm text-slate-500">Review required → Assigned</p><button className="mt-3 text-sm font-semibold text-[var(--pc-teal-action)]">View history</button></div>
      </div>
    </aside>
  </>;
}

function SearchPalette({ open, query, setQuery, onClose, onSelect }: { open: boolean; query: string; setQuery: (value: string) => void; onClose: () => void; onSelect: (screen: ScreenId) => void }) {
  const matches = SEARCH_ITEMS.filter((item) => (item.title + " " + item.meta + " " + item.kind).toLowerCase().includes(query.toLowerCase()));
  if (!open) return null;
  return <div className="fixed inset-0 z-[70] flex items-start justify-center bg-[#051a39]/35 px-4 pt-[12vh]" onMouseDown={onClose}>
    <div className="w-full max-w-2xl overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl" onMouseDown={(event) => event.stopPropagation()}>
      <div className="flex items-center gap-3 border-b border-slate-200 px-4 py-3">
        <span className="text-slate-400">⌕</span>
        <input autoFocus value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search patients, invoices, claims and work..." className="w-full border-0 bg-transparent py-2 text-base outline-none" />
        <kbd className="rounded border border-slate-200 bg-slate-50 px-2 py-1 text-[11px] text-slate-500">ESC</kbd>
      </div>
      <div className="max-h-[440px] overflow-y-auto p-2">
        {matches.map((item) => <button key={item.kind + item.title} onClick={() => onSelect(item.screen)} className="flex w-full items-center justify-between gap-4 rounded-xl px-3 py-3 text-left hover:bg-slate-50">
          <div><p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-400">{item.kind}</p><p className="mt-1 text-sm font-semibold text-slate-800">{item.title}</p><p className="mt-1 text-xs text-slate-500">{item.meta}</p></div><span className="text-slate-400">→</span>
        </button>)}
        {!matches.length ? <div className="p-8 text-center"><p className="font-semibold text-slate-700">No results</p><p className="mt-1 text-sm text-slate-500">Try a patient name, invoice number or claim reference.</p></div> : null}
      </div>
    </div>
  </div>;
}

function CommandCentre({ role, inspect }: { role: Role; inspect: (item: DrawerItem) => void }) {
  const roleCopy: Record<Role, string> = {
    owner: "Practice owner · revenue, collection and operational exceptions",
    claims: "Claims administrator · blockers, rejections and submission readiness",
    reception: "Front desk · appointments, requests and eligibility issues",
    practitioner: "Practitioner · today’s patients and coding confirmation",
  };
  return <div className="space-y-6">
    <div><p className="text-sm font-semibold text-[var(--pc-teal-action)]">Command Centre</p><h1 className="mt-1 text-3xl font-semibold">Good afternoon</h1><p className="mt-2 text-sm text-slate-500">{roleCopy[role]}</p></div>
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex items-center justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[0.1em] text-slate-500">Needs your attention</p><h2 className="mt-1 text-xl font-semibold">Resolve exceptions before routine work</h2></div><StatusBadge value="8 items" /></div>
      <div className="mt-5 divide-y divide-slate-100">
        {[
          ["7 claims blocked", "Two authorisation issues, three membership checks and two coding findings", "Blocked"],
          ["R184,500 revenue under review", "Underpayments, rejected claims and tariff variances require investigation", "Review required"],
          ["4 work items overdue", "Two assigned to you · two unassigned", "Overdue"],
        ].map((row) => <button key={row[0]} onClick={() => inspect({ title: row[0], subtitle: "Practice-wide exception", status: row[2], why: row[1], evidence: ["Source records are linked", "No destructive action has been taken", "Audit context is available"], action: "Open work queue" })} className="group flex w-full items-center justify-between gap-4 py-4 text-left hover:bg-slate-50">
          <div><p className="font-semibold text-slate-800">{row[0]}</p><p className="mt-1 text-sm text-slate-500">{row[1]}</p></div><span className="text-slate-400 transition group-hover:translate-x-1">→</span>
        </button>)}
      </div>
    </section>
    <section>
      <SectionTitle title="Today" note="Activity is secondary to exceptions, but still visible at a glance." />
      <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <Metric label="Appointments" value="26" note="4 remaining today" />
        <Metric label="Consultations" value="18" note="15 completed · 3 in progress" />
        <Metric label="Coding confirmed" value="16" note="2 awaiting practitioner confirmation" />
        <Metric label="Claims ready" value="11" note="Ready for authorisation" />
      </div>
    </section>
    <section className="grid gap-4 xl:grid-cols-[1.2fr_.8fr]">
      <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <SectionTitle title="My work" note="A personal action surface, not a replacement for Operations." action="Open all" />
        <div className="mt-4 divide-y divide-slate-100">
          {WORK_ROWS.slice(0, 4).map((row) => <button key={row.id} onClick={() => inspect({ title: row.task, subtitle: row.patient + " · " + row.id, status: row.status, why: "This item is preventing the related workflow from progressing.", evidence: ["Patient context is available", "Related claim evidence is linked", "Owner and due date are recorded"], action: "Resolve item" })} className="flex w-full items-center justify-between gap-4 py-3 text-left hover:bg-slate-50">
            <div><p className="text-sm font-semibold text-slate-800">{row.task}</p><p className="mt-1 text-xs text-slate-500">{row.patient} · {row.owner} · {row.due}</p></div><StatusBadge value={row.status} />
          </button>)}
        </div>
      </article>
      <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <SectionTitle title="Revenue pulse" note="Every number can be explained." />
        <div className="mt-4 space-y-3">
          <button onClick={() => inspect({ title: "Variance R160,000", subtitle: "Revenue composition", status: "Review required", why: "The variance is concentrated in five explainable categories.", evidence: ["R62,400 underpayment", "R41,800 rejected claims", "R23,700 authorisation failures", "R18,100 coding findings", "R14,000 late submissions"], action: "Investigate variance" })} className="w-full rounded-xl border border-slate-200 p-4 text-left hover:bg-slate-50"><p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Variance</p><p className="mt-2 text-2xl font-semibold text-[var(--pc-navy)]">R160,000</p><p className="mt-1 text-sm text-[var(--pc-teal-action)]">Why? →</p></button>
          <div className="grid grid-cols-2 gap-3"><div className="rounded-xl bg-slate-50 p-3"><p className="text-xs text-slate-500">Expected</p><p className="mt-1 text-lg font-semibold">R820,400</p></div><div className="rounded-xl bg-slate-50 p-3"><p className="text-xs text-slate-500">Actual</p><p className="mt-1 text-lg font-semibold">R660,400</p></div></div>
        </div>
      </article>
    </section>
  </div>;
}

function PatientRecord() {
  const [tab, setTab] = useState("Overview");
  return <div className="space-y-5">
    <header className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div><p className="text-sm font-semibold text-[var(--pc-teal-action)]">Patient Record</p><h1 className="mt-1 text-3xl font-semibold">Nomsa Moyo</h1><p className="mt-2 text-sm text-slate-500">PC-001284 · Female · 42 years</p></div>
        <div className="flex flex-wrap gap-2"><StatusBadge value="Membership verified" /><StatusBadge value="No account hold" /></div>
      </div>
      <div className="mt-5 grid gap-3 border-t border-slate-100 pt-4 md:grid-cols-3"><div><p className="text-xs text-slate-500">Scheme</p><p className="mt-1 text-sm font-semibold">Discovery Health</p></div><div><p className="text-xs text-slate-500">Plan</p><p className="mt-1 text-sm font-semibold">Classic Comprehensive</p></div><div><p className="text-xs text-slate-500">Member</p><p className="mt-1 text-sm font-semibold">••••4821</p></div></div>
    </header>
    <nav className="sticky top-0 z-20 overflow-x-auto rounded-xl border border-slate-200 bg-white px-2 shadow-sm">
      <div className="flex min-w-max gap-1">{["Overview", "Appointments", "Clinical", "Billing", "Claims 3", "Documents 8", "Communications 12"].map((name) => <button key={name} onClick={() => setTab(name)} className={cx("border-b-2 px-3 py-3 text-sm font-semibold", tab === name ? "border-[var(--pc-teal)] text-[var(--pc-navy)]" : "border-transparent text-slate-500 hover:text-slate-800")}>{name}</button>)}</div>
    </nav>
    <div className="grid gap-4 xl:grid-cols-[1.15fr_.85fr]">
      <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <SectionTitle title={tab} note="Patient context remains persistent while detail changes." />
        <div className="mt-5 space-y-4">
          {["Today · Membership re-verified", "22 Sep · Consultation completed", "22 Sep · Coding confirmed by Dr Tini", "21 Sep · Authorisation received"].map((item) => <div key={item} className="flex gap-3"><span className="mt-1.5 h-2.5 w-2.5 rounded-full bg-[var(--pc-teal)]" /><div><p className="text-sm font-semibold text-slate-800">{item}</p><p className="mt-1 text-sm text-slate-500">Supporting evidence and audit history available.</p></div></div>)}
        </div>
      </article>
      <div className="space-y-4">
        <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"><p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Upcoming appointment</p><p className="mt-2 font-semibold">29 Sep · 10:30</p><p className="mt-1 text-sm text-slate-500">Follow-up consultation · Dr Tini</p></article>
        <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"><p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Recent claims</p><div className="mt-3 space-y-3"><div><p className="text-sm font-semibold">CLM-260924-04</p><p className="text-xs text-slate-500">Blocked · authorisation missing</p></div><div><p className="text-sm font-semibold">CLM-260918-11</p><p className="text-xs text-slate-500">Paid · R1,180.00</p></div></div></article>
        <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"><p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Recent communication</p><p className="mt-2 text-sm font-semibold">Appointment reminder sent</p><p className="mt-1 text-xs text-slate-500">SMS · 24 Sep · 09:04</p></article>
      </div>
    </div>
  </div>;
}

function Operations({ inspect }: { inspect: (item: DrawerItem) => void }) {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("All");
  const [owner, setOwner] = useState("All");
  const [density, setDensity] = useState<"Comfortable" | "Compact">("Comfortable");
  const filtered = WORK_ROWS.filter((row) => (status === "All" || row.status === status) && (owner === "All" || row.owner === owner) && (row.task + " " + row.patient + " " + row.type).toLowerCase().includes(query.toLowerCase()));
  return <div className="space-y-5">
    <div><p className="text-sm font-semibold text-[var(--pc-teal-action)]">Operations</p><h1 className="mt-1 text-3xl font-semibold">Work queue</h1><p className="mt-2 text-sm text-slate-500">System of record for operational work. My Work is the personal attention layer.</p></div>
    <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
      <div className="grid gap-3 lg:grid-cols-[1fr_auto_auto_auto]">
        <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search work items..." className="rounded-lg border border-slate-200 px-3 py-2.5 text-sm outline-none focus:border-[var(--pc-blue)]" />
        <select value={status} onChange={(event) => setStatus(event.target.value)} className="rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm"><option>All</option><option>Overdue</option><option>Today</option><option>Blocked</option><option>Open</option></select>
        <select value={owner} onChange={(event) => setOwner(event.target.value)} className="rounded-lg border border-slate-200 bg-white px-3 py-2.5 text-sm"><option>All</option><option>Amanda</option><option>Lerato</option><option>Dr Tini</option><option>Unassigned</option></select>
        <button className="rounded-lg border border-slate-200 px-3 py-2.5 text-sm font-semibold">Save view</button>
      </div>
      {(status !== "All" || owner !== "All" || query) ? <div className="mt-3 flex flex-wrap items-center gap-2"><span className="text-xs font-semibold text-slate-500">Active filters</span>{status !== "All" ? <button onClick={() => setStatus("All")} className="rounded-full bg-slate-100 px-3 py-1 text-xs">Status: {status} ×</button> : null}{owner !== "All" ? <button onClick={() => setOwner("All")} className="rounded-full bg-slate-100 px-3 py-1 text-xs">Owner: {owner} ×</button> : null}{query ? <button onClick={() => setQuery("")} className="rounded-full bg-slate-100 px-3 py-1 text-xs">Search: {query} ×</button> : null}<button onClick={() => { setStatus("All"); setOwner("All"); setQuery(""); }} className="text-xs font-semibold text-[var(--pc-teal-action)]">Clear filters</button></div> : null}
    </section>
    <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
      <div className="flex items-center justify-between border-b border-slate-200 px-4 py-3"><p className="text-sm font-semibold text-slate-700">{filtered.length} work items</p><div className="flex rounded-lg border border-slate-200 p-0.5">{(["Comfortable", "Compact"] as const).map((mode) => <button key={mode} onClick={() => setDensity(mode)} className={cx("rounded-md px-3 py-1.5 text-xs font-semibold", density === mode ? "bg-slate-100 text-slate-800" : "text-slate-500")}>{mode}</button>)}</div></div>
      {filtered.length ? <div className="overflow-x-auto"><table className="w-full min-w-[840px]"><thead className="sticky top-0 bg-slate-50 text-left text-xs uppercase tracking-[0.06em] text-slate-500"><tr><th className="px-4 py-3">Work item</th><th className="px-4 py-3">Patient</th><th className="px-4 py-3">Type</th><th className="px-4 py-3">Owner</th><th className="px-4 py-3">Due</th><th className="px-4 py-3">State</th></tr></thead><tbody>{filtered.map((row) => <tr key={row.id} onClick={() => inspect({ title: row.task, subtitle: row.patient + " · " + row.id, status: row.status, why: row.type + " work must be resolved before the dependent workflow can progress.", evidence: ["Patient context linked", "Related workflow evidence linked", "Audit owner recorded"], action: "Resolve" })} className="cursor-pointer border-t border-slate-100 hover:bg-slate-50"><td className={cx("px-4 font-semibold text-slate-800", density === "Comfortable" ? "py-4" : "py-2.5")}>{row.task}<p className="mt-1 text-xs font-normal text-slate-400">{row.id}</p></td><td className="px-4 text-sm">{row.patient}</td><td className="px-4 text-sm">{row.type}</td><td className="px-4 text-sm">{row.owner}</td><td className="px-4 text-sm">{row.due}</td><td className="px-4"><StatusBadge value={row.status} /></td></tr>)}</tbody></table></div> : <div className="p-12 text-center"><p className="text-lg font-semibold text-slate-700">No work matches these filters</p><p className="mt-2 text-sm text-slate-500">Clear filters to return to the full queue.</p><button onClick={() => { setStatus("All"); setOwner("All"); setQuery(""); }} className="mt-4 rounded-lg bg-[var(--pc-teal-action)] px-4 py-2 text-sm font-semibold text-white">Clear filters</button></div>}
    </section>
  </div>;
}

function Billing({ inspect }: { inspect: (item: DrawerItem) => void }) {
  const [stage, setStage] = useState(0);
  const steps = ["Encounter", "Coding", "Invoice", "Pre-flight", "Authorisation", "Submission"];
  const stageCopy = [
    { state: "Blocked — 2 issues", cta: "Resolve 2 blocking issues", badge: "Blocked" },
    { state: "Ready to finalise", cta: "Finalise invoice", badge: "Ready" },
    { state: "Claim awaiting authorisation", cta: "Authorise claim", badge: "Review required" },
    { state: "Ready for submission", cta: "Submit claim", badge: "Ready" },
  ];
  const current = stageCopy[stage];
  return <div className="space-y-5">
    <div className="flex flex-wrap items-start justify-between gap-4"><div><p className="text-sm font-semibold text-[var(--pc-teal-action)]">Billing & Claim Pre-flight</p><h1 className="mt-1 text-3xl font-semibold">INV-2026-00421</h1><p className="mt-2 text-sm text-slate-500">Nomsa Moyo · 24 Sep 2026 · Discovery Health</p></div><div className="text-right"><StatusBadge value={current.badge} /><p className="mt-2 text-sm font-semibold text-slate-700">{current.state}</p><button onClick={() => stage === 0 ? inspect({ title: "Resolve 2 blocking issues", subtitle: "INV-2026-00421 · Nomsa Moyo", status: "Blocked", why: "The claim cannot progress because the authorisation number is missing and one tariff mismatch remains unresolved.", evidence: ["Membership verified", "ICD-10 and procedure complete", "Authorisation number missing", "Reference tariff differs by R240"], action: "Open first finding" }) : setStage((value) => Math.min(3, value + 1))} className="mt-3 rounded-lg bg-[var(--pc-teal-action)] px-4 py-2.5 text-sm font-semibold text-white">{current.cta}</button></div></div>
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"><p className="text-xs font-semibold uppercase tracking-[0.08em] text-slate-500">Workflow</p><div className="mt-5 flex items-center overflow-x-auto pb-2">{steps.map((step, index) => <div key={step} className="flex min-w-[140px] flex-1 items-center"><div className="flex flex-col items-center"><span className={cx("flex h-8 w-8 items-center justify-center rounded-full border text-xs font-semibold", index < 3 + stage ? "border-[var(--pc-teal)] bg-[var(--pc-teal)] text-white" : index === 3 + stage ? "border-amber-400 bg-amber-50 text-amber-800" : "border-slate-200 bg-white text-slate-400")}>{index < 3 + stage ? "✓" : index + 1}</span><span className="mt-2 text-xs font-semibold text-slate-600">{step}</span></div>{index < steps.length - 1 ? <div className="mx-2 h-px flex-1 bg-slate-200" /> : null}</div>)}</div></section>
    <div className="grid gap-4 xl:grid-cols-[1.15fr_.85fr]">
      <article className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"><div className="border-b border-slate-200 p-5"><SectionTitle title="Invoice lines" note="Financial values align right for scanability." /></div><table className="w-full"><thead className="bg-slate-50 text-left text-xs uppercase tracking-[0.06em] text-slate-500"><tr><th className="px-5 py-3">Code</th><th className="px-5 py-3">Description</th><th className="px-5 py-3 text-right">Expected</th><th className="px-5 py-3 text-right">Actual</th><th className="px-5 py-3 text-right">Variance</th></tr></thead><tbody><tr className="border-t border-slate-100"><td className="px-5 py-4 font-semibold">0190</td><td className="px-5 py-4 text-sm">Consultation</td><td className="px-5 py-4 text-right">R1,240</td><td className="px-5 py-4 text-right">R1,000</td><td className="px-5 py-4 text-right font-semibold text-rose-700">R240</td></tr></tbody></table></article>
      <article className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"><SectionTitle title="Pre-flight findings" note="Workflow state is more prominent than document status." /><div className="mt-4 space-y-3"><button onClick={() => inspect({ title: "Authorisation missing", subtitle: "Blocking finding", status: "Blocked", why: "The payer contract requires an authorisation reference for this service.", evidence: ["Referral received", "Membership verified", "No authorisation number captured"], action: "Capture authorisation" })} className="w-full rounded-xl border border-rose-200 bg-rose-50 p-4 text-left"><div className="flex items-center justify-between gap-3"><p className="font-semibold text-rose-900">Authorisation missing</p><StatusBadge value="Blocked" /></div><p className="mt-2 text-sm text-rose-800">Required before claim authorisation.</p></button><button onClick={() => inspect({ title: "Tariff mismatch", subtitle: "Contract finding", status: "Review required", why: "The actual line amount differs from the effective payer contract rate.", evidence: ["Expected R1,240", "Actual R1,000", "Variance R240"], action: "Review tariff" })} className="w-full rounded-xl border border-amber-200 bg-amber-50 p-4 text-left"><div className="flex items-center justify-between gap-3"><p className="font-semibold text-amber-900">Tariff mismatch</p><StatusBadge value="Review required" /></div><p className="mt-2 text-sm text-amber-800">Contract reference available.</p></button></div><div className="mt-5 border-t border-slate-200 pt-4"><p className="text-xs text-slate-500">Document state</p><p className="mt-1 text-sm font-semibold">Draft invoice · Membership verified</p></div></article>
    </div>
  </div>;
}

function RevenueControl({ inspect }: { inspect: (item: DrawerItem) => void }) {
  const [path, setPath] = useState<string[]>(["Revenue Control"]);
  const levels = ["GEMS", "Emerald Value", "Consultations", "0190", "14 claims"];
  const next = levels[path.length - 1];
  return <div className="space-y-5">
    <div><p className="text-sm font-semibold text-[var(--pc-teal-action)]">Revenue Control</p><h1 className="mt-1 text-3xl font-semibold">Why revenue is leaking</h1><p className="mt-2 text-sm text-slate-500">Scheme → plan → procedure → claim. No unexplained KPI.</p></div>
    <nav className="flex flex-wrap items-center gap-2 text-sm">{path.map((part, index) => <span key={part} className="flex items-center gap-2"><button onClick={() => setPath(path.slice(0, index + 1))} className="font-semibold text-[var(--pc-teal-action)] hover:underline">{part}</button>{index < path.length - 1 ? <span className="text-slate-300">/</span> : null}</span>)}</nav>
    <div className="grid gap-4 md:grid-cols-3"><Metric label="Expected" value="R820,400" note="Contract-derived reimbursement" /><Metric label="Actual" value="R660,400" note="Paid / recognised" /><Metric label="Variance" value="R160,000" note="Click to explain" attention onClick={() => inspect({ title: "Variance R160,000", subtitle: path.join(" / "), status: "Review required", why: "The headline variance is fully decomposed into actionable categories.", evidence: ["R62,400 underpayment", "R41,800 rejected claims", "R23,700 authorisation failures", "R18,100 coding findings", "R14,000 late submissions"], action: "Open underpayments" })} /></div>
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"><SectionTitle title={path.length === 1 ? "Scheme exposure" : path[path.length - 1]} note="Select a row to drill deeper while preserving the breadcrumb." /><div className="mt-4 divide-y divide-slate-100">
      {(path.length < 6 ? [
        { name: next || "14 claims", expected: "R603,800", actual: "R548,200", variance: "R55,600" },
        { name: path.length === 1 ? "Discovery Health" : "Other", expected: "R216,600", actual: "R112,200", variance: "R104,400" },
      ] : []).map((row, index) => <button key={row.name + index} onClick={() => index === 0 && next ? setPath([...path, next]) : inspect({ title: row.name, subtitle: path.join(" / "), status: "Review required", why: "This branch contains material reimbursement variance.", evidence: ["Expected " + row.expected, "Actual " + row.actual, "Variance " + row.variance], action: "Inspect claims" })} className="grid w-full grid-cols-[1fr_auto_auto_auto] gap-4 py-4 text-left hover:bg-slate-50"><span className="font-semibold">{row.name}</span><span className="text-right text-sm">{row.expected}</span><span className="text-right text-sm">{row.actual}</span><span className="text-right text-sm font-semibold text-rose-700">{row.variance}</span></button>)}
      {path.length >= 6 ? <div className="grid gap-3 py-2">{["CLM-260924-04 · Nomsa Moyo · R240", "CLM-260921-08 · Nandi Zulu · R1,180", "CLM-260919-12 · Peter Adams · R640"].map((claim) => <button key={claim} onClick={() => inspect({ title: claim.split(" · ")[0], subtitle: claim, status: "Review required", why: "Claim-level evidence explains the remaining procedure variance.", evidence: ["Payer response linked", "Contract rate linked", "Submission timeline available"], action: "Open claim" })} className="rounded-xl border border-slate-200 p-4 text-left hover:bg-slate-50">{claim}</button>)}</div> : null}
    </div></section>
  </div>;
}

function Code10({ inspect }: { inspect: (item: DrawerItem) => void }) {
  return <div className="space-y-5">
    <div><p className="text-sm font-semibold text-[var(--pc-teal-action)]">Code10</p><h1 className="mt-1 text-3xl font-semibold">Clinical Coding Intelligence</h1><p className="mt-2 text-sm text-slate-500">Practitioner confirmation remains explicit; the interface explains every blocking or warning finding.</p></div>
    <div className="grid gap-4 md:grid-cols-3"><Metric label="Awaiting confirmation" value="2" note="Practitioner action required" /><Metric label="Warnings" value="3" note="Non-blocking review" /><Metric label="Confirmed today" value="16" note="Append-only decisions" /></div>
    <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"><div className="border-b border-slate-200 p-5"><SectionTitle title="Coding work" note="Entire rows are actionable." /></div><table className="w-full min-w-[760px]"><thead className="bg-slate-50 text-left text-xs uppercase tracking-[0.06em] text-slate-500"><tr><th className="px-5 py-3">Patient</th><th className="px-5 py-3">Encounter</th><th className="px-5 py-3">Finding</th><th className="px-5 py-3">State</th></tr></thead><tbody>{[
      ["Nomsa Moyo", "ENC-24111", "Modifier requires confirmation", "Review required"],
      ["Peter Adams", "ENC-24107", "Diagnosis/procedure relationship", "Warning"],
      ["Thando Jacobs", "ENC-24098", "Coding confirmed", "Resolved"],
    ].map((row) => <tr key={row[1]} onClick={() => inspect({ title: row[2], subtitle: row[0] + " · " + row[1], status: row[3], why: row[3] === "Resolved" ? "This coding decision is complete and auditable." : "The proposed coding requires human review before downstream billing.", evidence: ["Governed source version captured", "Suggested code path recorded", "Practitioner confirmation required where applicable"], action: row[3] === "Resolved" ? "View decision" : "Review coding" })} className="cursor-pointer border-t border-slate-100 hover:bg-slate-50"><td className="px-5 py-4 font-semibold">{row[0]}</td><td className="px-5 py-4 text-sm">{row[1]}</td><td className="px-5 py-4 text-sm">{row[2]}</td><td className="px-5 py-4"><StatusBadge value={row[3]} /></td></tr>)}</tbody></table></section>
  </div>;
}

function States() {
  const [errorVisible, setErrorVisible] = useState(true);
  return <div className="space-y-5">
    <div><p className="text-sm font-semibold text-[var(--pc-teal-action)]">Production states</p><h1 className="mt-1 text-3xl font-semibold">Empty, loading and recovery</h1><p className="mt-2 text-sm text-slate-500">Polish is defined by what happens when ideal data is absent.</p></div>
    <div className="grid gap-4 xl:grid-cols-3">
      <article className="rounded-2xl border border-slate-200 bg-white p-6 text-center shadow-sm"><div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-emerald-50 text-emerald-700">✓</div><h2 className="mt-4 text-lg font-semibold">You’re caught up</h2><p className="mt-2 text-sm text-slate-500">No work currently requires your attention.</p></article>
      <article className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm"><div className="animate-pulse space-y-4"><div className="h-4 w-1/3 rounded bg-slate-200" /><div className="h-10 rounded bg-slate-100" /><div className="h-10 rounded bg-slate-100" /><div className="h-10 rounded bg-slate-100" /></div><p className="mt-5 text-sm font-semibold text-slate-600">Structured loading skeleton</p></article>
      <article className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">{errorVisible ? <><div className="flex h-10 w-10 items-center justify-center rounded-full bg-amber-50 text-amber-800">!</div><h2 className="mt-4 text-lg font-semibold">Membership verification unavailable</h2><p className="mt-2 text-sm leading-6 text-slate-500">The claim cannot proceed because eligibility could not be verified. Existing patient information has not been changed.</p><div className="mt-4 flex gap-2"><button onClick={() => setErrorVisible(false)} className="rounded-lg bg-[var(--pc-teal-action)] px-3 py-2 text-sm font-semibold text-white">Retry</button><button className="rounded-lg border border-slate-200 px-3 py-2 text-sm font-semibold">Edit membership</button></div></> : <><StatusBadge value="Verified" /><h2 className="mt-4 text-lg font-semibold">Membership verified</h2><p className="mt-2 text-sm text-slate-500">The workflow may continue.</p></>}</article>
    </div>
  </div>;
}

export function PracticeCtrlPrototype() {
  const [screen, setScreen] = useState<ScreenId>("command");
  const [collapsed, setCollapsed] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [drawer, setDrawer] = useState<DrawerItem>(null);
  const [workOpen, setWorkOpen] = useState(false);
  const [role, setRole] = useState<Role>("owner");

  useEffect(() => {
    const saved = window.localStorage.getItem("practicectrl.prototype.sidebar");
    setCollapsed(saved === "collapsed");
  }, []);

  useEffect(() => {
    window.localStorage.setItem("practicectrl.prototype.sidebar", collapsed ? "collapsed" : "expanded");
  }, [collapsed]);

  useEffect(() => {
    function onKey(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setPaletteOpen(true);
      }
      if (event.key === "Escape") {
        setPaletteOpen(false);
        setWorkOpen(false);
        setDrawer(null);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const activeLabel = useMemo(() => {
    if (screen === "command") return "Command Centre";
    for (const group of NAV_GROUPS) {
      const match = group.items.find((item) => item.id === screen);
      if (match) return match.label;
    }
    return "PracticeCtrl";
  }, [screen]);

  function navigate(next: ScreenId) {
    setScreen(next);
    setPaletteOpen(false);
    setQuery("");
  }

  return <div className="min-h-screen bg-[var(--pc-canvas)] text-[var(--pc-ink)]">
    <div className="flex min-h-screen">
      <aside className={cx("sticky top-0 h-screen shrink-0 overflow-hidden bg-[var(--pc-navy)] text-white transition-[width] duration-200", collapsed ? "w-[72px]" : "w-[264px]")}>
        <div className="flex h-full flex-col">
          <div className="flex h-[76px] items-center border-b border-white/10 px-3">
            <button onClick={() => navigate("command")} className={cx("flex items-center gap-3 overflow-hidden", collapsed ? "justify-center" : "")} title="PracticeCtrl Command Centre">
              <img src={collapsed ? "/brand/practicectrl-icon-full-colour.png" : "/brand/practicectrl-logo-white-on-navy.png"} alt="PracticeCtrl" className={collapsed ? "h-10 w-10 rounded bg-white p-1.5 object-contain" : "h-9 w-auto max-w-[190px] object-contain"} />
            </button>
          </div>
          <nav className="flex-1 overflow-y-auto px-2 py-4">
            <button onClick={() => navigate("command")} className={cx("mb-5 flex w-full items-center rounded-lg px-3 py-2.5 text-sm font-semibold", screen === "command" ? "bg-white/12 text-white" : "text-white/70 hover:bg-white/8 hover:text-white", collapsed ? "justify-center" : "gap-3")} title="Command Centre"><span className="flex h-7 w-7 items-center justify-center rounded-md border border-white/15 text-[11px]">C</span>{!collapsed ? <span>Command Centre</span> : null}</button>
            <div className="space-y-5">{NAV_GROUPS.map((group) => <div key={group.label}>{!collapsed ? <p className="px-3 text-[10px] font-semibold tracking-[0.16em] text-white/40">{group.label}</p> : null}<div className="mt-2 space-y-1">{group.items.map((item) => <button key={item.id} onClick={() => navigate(item.id)} title={item.label} className={cx("flex w-full items-center rounded-lg px-3 py-2.5 text-sm font-medium", screen === item.id ? "bg-white/12 text-white" : "text-white/68 hover:bg-white/8 hover:text-white", collapsed ? "justify-center" : "gap-3")}><span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md border border-white/15 text-[10px] font-semibold">{item.glyph}</span>{!collapsed ? <span className="truncate">{item.label}</span> : null}</button>)}</div></div>)}</div>
          </nav>
          <div className="border-t border-white/10 p-3"><button onClick={() => setCollapsed((value) => !value)} className={cx("flex w-full items-center rounded-lg px-3 py-2.5 text-sm font-semibold text-white/70 hover:bg-white/8 hover:text-white", collapsed ? "justify-center" : "gap-3")}><span>{collapsed ? "›" : "‹"}</span>{!collapsed ? <span>Collapse navigation</span> : null}</button></div>
        </div>
      </aside>

      <div className="min-w-0 flex-1">
        <header className="sticky top-0 z-30 flex h-[76px] items-center justify-between gap-4 border-b border-slate-200 bg-white/95 px-5 backdrop-blur">
          <div><p className="text-xs font-semibold uppercase tracking-[0.1em] text-slate-400">PracticeCtrl prototype</p><p className="mt-1 text-sm font-semibold text-[var(--pc-navy)]">{activeLabel}</p></div>
          <div className="flex items-center gap-2">
            <button onClick={() => setPaletteOpen(true)} className="hidden min-w-[290px] items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-left text-sm text-slate-500 md:flex"><span>Search PracticeCtrl...</span><kbd className="rounded border border-slate-200 bg-white px-2 py-1 text-[10px]">⌘K</kbd></button>
            <div className="relative"><button onClick={() => setWorkOpen((value) => !value)} className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50">My work · 8</button>{workOpen ? <div className="absolute right-0 mt-2 w-[360px] overflow-hidden rounded-xl border border-slate-200 bg-white shadow-xl"><div className="border-b border-slate-200 p-4"><p className="font-semibold">My work</p><p className="mt-1 text-xs text-slate-500">2 overdue · 3 today · 1 claim blocker · 2 revenue cases</p></div><div className="divide-y divide-slate-100">{WORK_ROWS.slice(0, 4).map((row) => <button key={row.id} onClick={() => { setWorkOpen(false); setScreen("operations"); setDrawer({ title: row.task, subtitle: row.patient + " · " + row.id, status: row.status, why: "This work item currently requires attention.", evidence: ["Owner assigned", "Due date recorded", "Related workflow linked"], action: "Resolve item" }); }} className="flex w-full items-center justify-between gap-3 p-4 text-left hover:bg-slate-50"><div><p className="text-sm font-semibold">{row.task}</p><p className="mt-1 text-xs text-slate-500">{row.patient}</p></div><StatusBadge value={row.status} /></button>)}</div></div> : null}</div>
            <select value={role} onChange={(event) => setRole(event.target.value as Role)} className="rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700"><option value="owner">Practice owner</option><option value="claims">Claims admin</option><option value="reception">Reception</option><option value="practitioner">Practitioner</option></select>
            <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[var(--pc-navy)] text-xs font-semibold text-white">LL</div>
          </div>
        </header>

        <main className="mx-auto w-full max-w-[1580px] p-5 lg:p-7">
          {screen === "command" ? <CommandCentre role={role} inspect={setDrawer} /> : null}
          {screen === "patient" ? <PatientRecord /> : null}
          {screen === "operations" ? <Operations inspect={setDrawer} /> : null}
          {screen === "billing" ? <Billing inspect={setDrawer} /> : null}
          {screen === "revenue" ? <RevenueControl inspect={setDrawer} /> : null}
          {screen === "code10" ? <Code10 inspect={setDrawer} /> : null}
          {screen === "states" ? <States /> : null}
        </main>
      </div>
    </div>
    <SearchPalette open={paletteOpen} query={query} setQuery={setQuery} onClose={() => setPaletteOpen(false)} onSelect={navigate} />
    <Drawer item={drawer} onClose={() => setDrawer(null)} />
  </div>;
}
