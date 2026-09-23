"use client";

import { useCallback, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ClinicalCodingExplorer } from "./ClinicalCodingExplorer";
import type { ClinicalCodingCandidate } from "../clinical-coding-explorer-model";
import {
  confirmCodingCandidate,
  searchWithinCodingSession,
  startCodingSession,
  type CodingSessionRecord,
} from "../integration/clinical-coding-controller";

export type ClinicalCodingWorkspaceProps = {
  supabase: SupabaseClient;
  practiceId: string;
  patientId?: string | null;
  encounterId?: string | null;
  serviceDate: string;
  patientSex?: "M" | "F" | "U" | null;
  onConfirmed?: (args: {
    decisionId: string;
    candidate: ClinicalCodingCandidate;
    position: "primary" | "secondary";
    sessionId: string;
  }) => void | Promise<void>;
};

export function ClinicalCodingWorkspace({
  supabase,
  practiceId,
  patientId = null,
  encounterId = null,
  serviceDate,
  patientSex = null,
  onConfirmed,
}: ClinicalCodingWorkspaceProps) {
  const [session, setSession] = useState<CodingSessionRecord | null>(null);
  const [position, setPosition] = useState<"primary" | "secondary">("primary");
  const [notice, setNotice] = useState<string | null>(null);

  const demographicsLabel = useMemo(() => {
    const sex = patientSex === "M" ? "Male" : patientSex === "F" ? "Female" : "Sex not specified";
    return `${serviceDate} · ${sex}`;
  }, [patientSex, serviceDate]);

  const ensureSession = useCallback(async () => {
    if (session) return session;
    const created = await startCodingSession(supabase, {
      practiceId,
      patientId,
      encounterId,
      serviceDate,
      patientSex,
    });
    setSession(created);
    return created;
  }, [encounterId, patientId, patientSex, practiceId, serviceDate, session, supabase]);

  const search = useCallback(async (query: string) => {
    setNotice(null);
    const activeSession = await ensureSession();
    return searchWithinCodingSession(supabase, activeSession, query, { targetPosition: position });
  }, [ensureSession, position, supabase]);

  const confirm = useCallback(async (candidate: ClinicalCodingCandidate) => {
    const activeSession = await ensureSession();
    const decisionId = await confirmCodingCandidate(supabase, {
      sessionId: activeSession.id,
      codeId: candidate.codeId,
      position,
    });
    setNotice(`${candidate.code} confirmed as ${position} diagnosis.`);
    await onConfirmed?.({ decisionId, candidate, position, sessionId: activeSession.id });
  }, [ensureSession, onConfirmed, position, supabase]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border p-3">
        <div>
          <p className="text-sm font-medium">Coding context</p>
          <p className="text-xs text-muted-foreground">{demographicsLabel}</p>
        </div>
        <div className="inline-flex rounded-md border p-1" aria-label="Diagnosis position">
          {(["primary", "secondary"] as const).map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={position === value}
              onClick={() => setPosition(value)}
              className={`rounded px-3 py-1.5 text-sm ${position === value ? "bg-foreground text-background" : ""}`}
            >
              {value === "primary" ? "Primary" : "Secondary"}
            </button>
          ))}
        </div>
      </div>

      {notice && (
        <div role="status" className="rounded-md border p-3 text-sm">
          {notice}
        </div>
      )}

      <ClinicalCodingExplorer search={search} onConfirm={confirm} />
    </div>
  );
}
