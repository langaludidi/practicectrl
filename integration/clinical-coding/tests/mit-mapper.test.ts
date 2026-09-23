import { describe, expect, it } from "vitest";
import { assertMitHeaders, mapMitRow, REQUIRED_MIT_COLUMNS } from "../../../src/features/clinical-coding/mit-mapper";

const validRow = {
  Number: "0000000001",
  Chapter_No: "CHAPTER I",
  Chapter_Desc: "Example chapter",
  Group_Code: "001",
  Group_Desc: "Example group",
  ICD10_3_Code: "A08",
  ICD10_3_Code_Desc: "Example three-character description",
  ICD10_Code: "A08",
  WHO_Full_Desc: "Example official description",
  Valid_ICD10_ClinicalUse: "Y",
  Valid_ICD10_Primary: "Y",
  Valid_ICD10_Asterisk: "N",
  Valid_ICD10_Dagger: "N",
  Valid_ICD10_Sequelae: "N",
  Age_Range: "",
  Gender: "U",
  Status: "A",
  WHO_Start_Date: "20051101",
  WHO_End_Date: "",
  WHO_Revision_History: "",
  SA_Start_Date: "",
  SA_End_Date: "",
  SA_Revision_History: "",
  Comment: "",
};

describe("MIT mapper", () => {
  it("maps the published NDoH column shape without changing official text", () => {
    const mapped = mapMitRow(validRow);
    expect(mapped.code).toBe("A08");
    expect(mapped.normalized_code).toBe("A08");
    expect(mapped.official_description).toBe("Example official description");
    expect(mapped.valid_clinical_use).toBe(true);
    expect(mapped.who_start_date).toBe("2005-11-01");
  });

  it("rejects non Y/N validity flags", () => {
    expect(() => mapMitRow({ ...validRow, Valid_ICD10_Primary: "MAYBE" })).toThrow();
  });

  it("rejects missing official code", () => {
    expect(() => mapMitRow({ ...validRow, ICD10_Code: "" })).toThrow();
  });

  it("detects source schema drift", () => {
    expect(() => assertMitHeaders(REQUIRED_MIT_COLUMNS.filter((x) => x !== "WHO_Full_Desc"))).toThrow(/WHO_Full_Desc/);
  });
});
