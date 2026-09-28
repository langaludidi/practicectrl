import { describe, expect, it } from "vitest";
import { safeNext } from "../../../lib/auth/safe-next";

const origin = new URL("https://practicectrl.example/auth/callback");

describe("authentication return URL", () => {
  it("preserves an internal destination and its invitation query", () => {
    expect(safeNext("/onboarding/accept?invite=123", origin).href)
      .toBe("https://practicectrl.example/onboarding/accept?invite=123");
  });

  it.each(["//elsewhere.example", "/\\elsewhere.example", "https://elsewhere.example", "\\\\elsewhere.example"])(
    "does not redirect to another origin: %s", (value) => {
      expect(safeNext(value, origin).href).toBe("https://practicectrl.example/dashboard");
    },
  );
});
