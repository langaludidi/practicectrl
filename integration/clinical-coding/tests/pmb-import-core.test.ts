import { describe, expect, it } from "vitest";
import { detectPmbColumnMap, mapPmbRow } from "../../../src/features/clinical-coding/pmb-import-core";

describe("PMB workbook mapping", () => {
  it("detects a conservative common header shape", () => {
    const map = detectPmbColumnMap(["ICD-10 Code", "DTP Number", "PMB Descriptor"]);
    expect(map.icd10Code).toBe("ICD-10 Code");
    expect(map.dtpNumber).toBe("DTP Number");
  });

  it("refuses to guess when no ICD-10 column can be identified", () => {
    expect(() => detectPmbColumnMap(["Condition", "Descriptor"])).toThrow(/explicit PMB column map/);
  });

  it("normalises code punctuation but preserves the original code", () => {
    const mapped = mapPmbRow(
      { "ICD-10 Code": "E11.9", "PMB Descriptor": "Example" },
      { icd10Code: "ICD-10 Code", pmbDescriptor: "PMB Descriptor" },
    );
    expect(mapped.icd10_code).toBe("E11.9");
    expect(mapped.normalized_code).toBe("E119");
  });
});
