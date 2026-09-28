import { describe, expect, it } from "vitest";
import {
  STAFF_ROLES,
  canManageBilling,
  canManageRecovery,
  canManageRevenueControl,
  canManageVeriClaimImports,
  canViewRevenue,
  type StaffRole,
} from "../../../lib/auth/roles";

type FinancialAccess = {
  read: boolean;
  billingTransactions: boolean;
  revenueControl: boolean;
  recovery: boolean;
  imports: boolean;
};

const expected: Record<StaffRole, FinancialAccess> = {
  practitioner: { read: false, billingTransactions: false, revenueControl: false, recovery: false, imports: false },
  reception: { read: false, billingTransactions: false, revenueControl: false, recovery: false, imports: false },
  billing: { read: true, billingTransactions: true, revenueControl: true, recovery: true, imports: true },
  finance: { read: true, billingTransactions: false, revenueControl: true, recovery: true, imports: false },
  coder: { read: false, billingTransactions: false, revenueControl: false, recovery: false, imports: false },
  practice_manager: { read: true, billingTransactions: true, revenueControl: true, recovery: true, imports: true },
  clinical_admin: { read: false, billingTransactions: false, revenueControl: false, recovery: false, imports: false },
  auditor: { read: true, billingTransactions: false, revenueControl: false, recovery: false, imports: false },
  system_admin: { read: true, billingTransactions: true, revenueControl: true, recovery: true, imports: true },
};

describe("financial access contract", () => {
  it("defines the nine operational roles once", () => {
    expect(STAFF_ROLES).toEqual([
      "practitioner", "reception", "billing", "finance", "coder", "practice_manager", "clinical_admin", "auditor", "system_admin",
    ]);
  });

  for (const role of STAFF_ROLES) {
    it(`enforces the intended financial capability set for ${role}`, () => {
      const access = expected[role];
      expect(canViewRevenue(role)).toBe(access.read);
      expect(canManageBilling(role)).toBe(access.billingTransactions);
      expect(canManageRevenueControl(role)).toBe(access.revenueControl);
      expect(canManageRecovery(role)).toBe(access.recovery);
      expect(canManageVeriClaimImports(role)).toBe(access.imports);
    });
  }

  it("keeps Finance in the oversight and recovery path, not the billing transaction path", () => {
    expect(canViewRevenue("finance")).toBe(true);
    expect(canManageRevenueControl("finance")).toBe(true);
    expect(canManageRecovery("finance")).toBe(true);
    expect(canManageBilling("finance")).toBe(false);
    expect(canManageVeriClaimImports("finance")).toBe(false);
  });
});
