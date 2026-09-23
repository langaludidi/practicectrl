export type ValidationSeverity = "INFO" | "ADVISORY" | "WARNING" | "BLOCKING";

export type Sex = "M" | "F" | "U" | null;

export type CodeForValidation = {
  code: string;
  validClinicalUse: boolean;
  validPrimary: boolean;
  validAsterisk: boolean;
  validDagger: boolean;
  gender: Sex;
  saStartDate: string | null;
  saEndDate: string | null;
};

export type ValidationContext = {
  position: "primary" | "secondary";
  patientSex: Sex;
  serviceDate: string; // YYYY-MM-DD
};

export type ValidationMessage = {
  ruleCode: string;
  severity: ValidationSeverity;
  message: string;
  blocking: boolean;
};

const isoDate = (s: string): number => {
  const t = Date.parse(`${s}T00:00:00Z`);
  if (Number.isNaN(t)) throw new Error(`Invalid ISO date: ${s}`);
  return t;
};

/**
 * Deterministic MIT-level checks only. PHISC relationship rules (ECC, dagger/asterisk pairing,
 * etc.) are added from versioned rule data in a later adapter rather than guessed here.
 */
export function validateMitCode(code: CodeForValidation, ctx: ValidationContext): ValidationMessage[] {
  const messages: ValidationMessage[] = [];

  if (!code.validClinicalUse) {
    messages.push({
      ruleCode: "CODE_NOT_CLINICALLY_VALID",
      severity: "BLOCKING",
      blocking: true,
      message: `${code.code} is not marked valid for clinical use in the selected South African MIT release.`,
    });
  }

  if (ctx.position === "primary" && !code.validPrimary) {
    messages.push({
      ruleCode: "PRIMARY_NOT_ALLOWED",
      severity: "BLOCKING",
      blocking: true,
      message: `${code.code} is not marked valid in the primary/first position in the selected MIT release.`,
    });
  }

  if (code.gender && code.gender !== "U" && ctx.patientSex && ctx.patientSex !== "U" && code.gender !== ctx.patientSex) {
    messages.push({
      ruleCode: "GENDER_CONFLICT",
      severity: "WARNING",
      blocking: false,
      message: `${code.code} carries a ${code.gender === "M" ? "male" : "female"} MIT gender indicator that conflicts with the recorded patient sex. Verify the clinical record before confirming.`,
    });
  }

  const service = isoDate(ctx.serviceDate);
  if (code.saStartDate && service < isoDate(code.saStartDate)) {
    messages.push({
      ruleCode: "BEFORE_SA_EFFECTIVE_DATE",
      severity: "BLOCKING",
      blocking: true,
      message: `${code.code} was not yet effective in South Africa on the service date.`,
    });
  }
  if (code.saEndDate && service > isoDate(code.saEndDate)) {
    messages.push({
      ruleCode: "AFTER_SA_END_DATE",
      severity: "BLOCKING",
      blocking: true,
      message: `${code.code} was no longer effective in South Africa on the service date.`,
    });
  }

  if (code.validAsterisk) {
    messages.push({
      ruleCode: "ASTERISK_RELATIONSHIP_REVIEW",
      severity: "WARNING",
      blocking: false,
      message: `${code.code} is marked as an asterisk code. Review the applicable South African dagger/asterisk sequencing rule before confirmation.`,
    });
  }
  if (code.validDagger) {
    messages.push({
      ruleCode: "DAGGER_RELATIONSHIP_REVIEW",
      severity: "WARNING",
      blocking: false,
      message: `${code.code} is marked as a dagger code. Review the applicable South African dagger/asterisk relationship before confirmation.`,
    });
  }

  return messages;
}
