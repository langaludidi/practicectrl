export function money(value: number | string | null | undefined) {
  const n = typeof value === "string" ? Number(value) : Number(value ?? 0);
  return new Intl.NumberFormat("en-ZA", { style: "currency", currency: "ZAR" }).format(Number.isFinite(n) ? n : 0);
}

export function shortDate(value: string | null | undefined) {
  if (!value) return "—";
  const d = new Date(value.length === 10 ? `${value}T00:00:00` : value);
  return Number.isNaN(d.valueOf()) ? value : new Intl.DateTimeFormat("en-ZA", { dateStyle: "medium" }).format(d);
}

export function shortDateTime(value: string | null | undefined) {
  if (!value) return "—";
  const d = new Date(value);
  return Number.isNaN(d.valueOf()) ? value : new Intl.DateTimeFormat("en-ZA", { dateStyle: "medium", timeStyle: "short" }).format(d);
}
