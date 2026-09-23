"use client";

type Column = {
  key: string;
  label: string;
  align?: "left" | "right";
};

type Row = Record<string, string | number | null>;

function csvCell(value: string | number | null) {
  const text = value == null ? "" : String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

export function ReportTable({
  title,
  subtitle,
  columns,
  rows,
}: {
  title: string;
  subtitle?: string;
  columns: Column[];
  rows: Row[];
}) {
  function downloadCsv() {
    const csv = [
      columns.map(column => csvCell(column.label)).join(","),
      ...rows.map(row => columns.map(column => csvCell(row[column.key] ?? "")).join(",")),
    ].join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") + ".csv";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
  }

  return <section className="border border-[#dce3ea] bg-white">
    <div className="flex flex-wrap items-start justify-between gap-4 border-b border-[#dce3ea] px-4 py-4 sm:px-5">
      <div>
        <h2 className="text-base font-semibold text-[#051a39]">{title}</h2>
        {subtitle ? <p className="mt-1 max-w-4xl text-sm leading-6 text-[#526276]">{subtitle}</p> : null}
        <p className="mt-1 text-xs font-medium text-[#64748b]">{rows.length} {rows.length === 1 ? "row" : "rows"} shown</p>
      </div>
      <div className="flex gap-2 print:hidden">
        <button type="button" onClick={downloadCsv} className="h-9 border border-[#067c80] bg-white px-3 text-xs font-semibold text-[#067c80] hover:bg-[#f0fbfb]">Download CSV</button>
        <button type="button" onClick={() => window.print()} className="h-9 border border-[#067c80] bg-[#067c80] px-3 text-xs font-semibold text-white hover:bg-[#056b6e]">Print</button>
      </div>
    </div>
    <div className="overflow-x-auto">
      <table className="w-full min-w-[760px] text-left text-sm">
        <thead className="bg-[#f8fafc]">
          <tr>{columns.map(column => <th key={column.key} className={`border-b border-[#dce3ea] px-4 py-3 text-xs font-semibold uppercase tracking-wide text-[#475569] ${column.align === "right" ? "text-right" : ""}`}>{column.label}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((row,index) => <tr key={index} className="border-b border-[#edf1f5] last:border-b-0">
            {columns.map(column => <td key={column.key} className={`px-4 py-3 align-top text-[#26384d] ${column.align === "right" ? "text-right tabular-nums" : ""}`}>{row[column.key] ?? "—"}</td>)}
          </tr>)}
        </tbody>
      </table>
    </div>
    {!rows.length ? <div className="px-5 py-10 text-center text-sm text-[#64748b]">No records are currently available for this practice and report preset.</div> : null}
  </section>;
}
