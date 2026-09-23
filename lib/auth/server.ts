import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { StaffRole } from "./roles";

export const ACTIVE_PRACTICE_COOKIE = "pc_practice_id";

export type PracticeMembership = {
  practiceId: string;
  practiceName: string;
  tenantSlug: string;
  role: StaffRole;
};

export type PlatformRole = "platform_owner" | "platform_admin" | "support_auditor";

export type StaffContext = {
  userId: string;
  email: string | null;
  practiceId: string;
  practiceName: string;
  tenantSlug: string;
  role: StaffRole;
  memberships: PracticeMembership[];
  platformRole: PlatformRole | null;
  aal: "aal1" | "aal2" | null;
};

export type PracticeSelectionContext = {
  userId: string;
  email: string | null;
  memberships: PracticeMembership[];
  preferredPracticeId: string | null;
  platformRole: PlatformRole | null;
  aal: "aal1" | "aal2" | null;
};

function normaliseMemberships(rows: any[] | null): PracticeMembership[] {
  return (rows ?? []).flatMap((row: any) => {
    const practice = Array.isArray(row.practice) ? row.practice[0] : row.practice;
    if (!practice?.id || !practice?.active) return [];
    return [{
      practiceId: String(practice.id),
      practiceName: String(practice.name),
      tenantSlug: String(practice.tenant_slug),
      role: row.role as StaffRole,
    }];
  });
}

async function loadIdentity() {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) redirect("/login");

  const [{ data: rows, error: membershipError }, { data: preference }, { data: platform }, { data: aalData, error: aalError }] = await Promise.all([
    supabase
      .from("practice_staff_member")
      .select("practice_id,role,practice:practice!inner(id,name,tenant_slug,active)")
      .eq("user_id", data.user.id)
      .eq("active", true)
      .eq("practice.active", true)
      .order("created_at"),
    supabase
      .from("user_practice_preference")
      .select("last_practice_id")
      .eq("user_id", data.user.id)
      .maybeSingle(),
    supabase
      .from("platform_operator")
      .select("role")
      .eq("user_id", data.user.id)
      .eq("active", true)
      .maybeSingle(),
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
  ]);

  if (membershipError) throw membershipError;
  if (aalError) throw aalError;

  return {
    userId: data.user.id,
    email: data.user.email ?? null,
    memberships: normaliseMemberships(rows as any[] | null),
    preferredPracticeId: preference?.last_practice_id ? String(preference.last_practice_id) : null,
    platformRole: (platform?.role as PlatformRole | undefined) ?? null,
    aal: (aalData?.currentLevel as "aal1" | "aal2" | null | undefined) ?? null,
  } satisfies PracticeSelectionContext;
}

export async function getPracticeSelectionContext(): Promise<PracticeSelectionContext> {
  return loadIdentity();
}

async function resolveStaffContext(requireAal2: boolean): Promise<StaffContext> {
  const identity = await loadIdentity();
  const store = await cookies();
  const cookiePracticeId = store.get(ACTIVE_PRACTICE_COOKIE)?.value ?? null;

  const selected =
    identity.memberships.find((membership) => membership.practiceId === cookiePracticeId) ??
    identity.memberships.find((membership) => membership.practiceId === identity.preferredPracticeId) ??
    (identity.memberships.length === 1 ? identity.memberships[0] : null);

  if (!selected) {
    if (identity.memberships.length === 0 && identity.platformRole) redirect("/platform/tenants");
    if (identity.memberships.length === 0) redirect("/invitations");
    redirect("/select-practice");
  }

  if (requireAal2 && identity.aal !== "aal2") redirect("/mfa");

  return {
    userId: identity.userId,
    email: identity.email,
    practiceId: selected.practiceId,
    practiceName: selected.practiceName,
    tenantSlug: selected.tenantSlug,
    role: selected.role,
    memberships: identity.memberships,
    platformRole: identity.platformRole,
    aal: identity.aal,
  };
}

/** Authorised staff identity for the selected practice, regardless of current MFA assurance level. */
export async function requireStaffIdentity(): Promise<StaffContext> {
  return resolveStaffContext(false);
}

/** Staff-only selected-practice context. MFA/AAL2 is mandatory. */
export async function requireStaffContext(): Promise<StaffContext> {
  return resolveStaffContext(true);
}

export async function requirePlatformContext(): Promise<{
  userId: string;
  email: string | null;
  role: PlatformRole;
  aal: "aal2";
}> {
  const identity = await loadIdentity();
  if (!identity.platformRole) redirect(identity.memberships.length ? "/dashboard" : "/invitations");
  if (identity.aal !== "aal2") redirect("/mfa?next=/platform/tenants");
  return {
    userId: identity.userId,
    email: identity.email,
    role: identity.platformRole,
    aal: "aal2",
  };
}
