import type { CodingCandidateCard } from "./coding-ui-contract";
import type { PmbUiState } from "./pmb-intelligence";

export type ClinicalCodingCandidate = CodingCandidateCard & {
  explanation?: string;
  pmb: PmbUiState;
  sourceLabel: string;
  canConfirm: boolean;
};

export type ClinicalCodingExplorerState =
  | { kind: "idle" }
  | { kind: "loading"; query: string }
  | { kind: "ready"; query: string; candidates: ClinicalCodingCandidate[] }
  | { kind: "empty"; query: string; message: string }
  | { kind: "error"; query: string; message: string };

export function canConfirmCandidate(candidate: CodingCandidateCard): boolean {
  return candidate.validityLabel === "SA-valid" && !candidate.warnings.some((x) => x.blocking);
}
