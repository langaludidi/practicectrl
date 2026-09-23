"use client";

import { ChangeEvent, FormEvent, useMemo, useState } from "react";
import type { ClinicalCodingCandidate } from "../clinical-coding-explorer-model";

type Props = {
  initialQuery?: string;
  search: (query: string) => Promise<ClinicalCodingCandidate[]>;
  onConfirm: (candidate: ClinicalCodingCandidate) => Promise<void> | void;
};

export function ClinicalCodingExplorer({ initialQuery = "", search, onConfirm }: Props) {
  const [query, setQuery] = useState(initialQuery);
  const [results, setResults] = useState<ClinicalCodingCandidate[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasQuery = useMemo(() => query.trim().length >= 2, [query]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!hasQuery) return;
    setLoading(true);
    setError(null);
    try {
      setResults(await search(query.trim()));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Coding search failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <section aria-labelledby="coding-explorer-heading" className="mx-auto w-full max-w-4xl space-y-5">
      <div className="space-y-1">
        <h1 id="coding-explorer-heading" className="text-2xl font-semibold tracking-tight">
          Clinical coding
        </h1>
        <p className="text-sm text-muted-foreground">
          Search a diagnosis, clinical term, abbreviation or South African ICD-10 code.
        </p>
      </div>

      <form onSubmit={submit} className="flex gap-2" role="search">
        <label className="sr-only" htmlFor="icd-search">Search ICD-10</label>
        <input
          id="icd-search"
          value={query}
          onChange={(e: ChangeEvent<HTMLInputElement>) => setQuery(e.target.value)}
          placeholder="e.g. type 2 diabetes with renal involvement"
          autoComplete="off"
          className="min-h-11 flex-1 rounded-md border bg-background px-3 text-sm outline-none focus-visible:ring-2"
        />
        <button
          type="submit"
          disabled={!hasQuery || loading}
          className="min-h-11 rounded-md border px-4 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-50"
        >
          {loading ? "Searching…" : "Search"}
        </button>
      </form>

      {error && <div role="alert" className="rounded-md border p-3 text-sm">{error}</div>}
      {!loading && hasQuery && !error && results.length === 0 && (
        <p className="text-sm text-muted-foreground">No matching South African ICD-10 codes found.</p>
      )}

      <div className="space-y-3" aria-live="polite">
        {results.map((candidate) => (
          <article key={candidate.codeId} className="rounded-lg border bg-card p-4 shadow-sm">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-mono text-lg font-semibold">{candidate.code}</span>
                  <span className="rounded-full border px-2 py-0.5 text-xs">{candidate.matchLabel}</span>
                  <span className="rounded-full border px-2 py-0.5 text-xs">{candidate.validityLabel}</span>
                </div>
                <h2 className="mt-2 font-medium">{candidate.officialDescription}</h2>
                {candidate.explanation && <p className="mt-2 text-sm text-muted-foreground">{candidate.explanation}</p>}
              </div>
              <button
                type="button"
                disabled={!candidate.canConfirm}
                onClick={() => onConfirm(candidate)}
                className="rounded-md border px-3 py-2 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-50"
              >
                Confirm code
              </button>
            </div>

            {candidate.warnings.length > 0 && (
              <div className="mt-4 space-y-2" aria-label="Coding validation">
                {candidate.warnings.map((warning) => (
                  <div key={`${candidate.code}-${warning.ruleCode}`} className="rounded-md border p-3 text-sm">
                    <strong>{warning.blocking ? "Action required" : "Review"}:</strong> {warning.message}
                  </div>
                ))}
              </div>
            )}

            <div className="mt-4 border-t pt-3 text-sm">
              <strong>{candidate.pmb.label}</strong>
              {candidate.pmb.kind === "possible" && (
                <p className="mt-1 text-muted-foreground">
                  The CMS coded list identifies a possible relationship only. Review the applicable PMB descriptor and clinical criteria before confirming PMB status.
                </p>
              )}
            </div>

            <details className="mt-3 text-sm">
              <summary className="cursor-pointer font-medium">Sources and coding detail</summary>
              <div className="mt-2 space-y-1 text-muted-foreground">
                <p>{candidate.sourceLabel}</p>
                <p>Source release: {candidate.sourceReleaseId}</p>
                <p>{candidate.primaryLabel}</p>
              </div>
            </details>
          </article>
        ))}
      </div>
    </section>
  );
}
