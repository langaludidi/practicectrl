import { AppShell } from "@/components/AppShell";
import { requireStaffContext } from "@/lib/auth/server";
export default async function StaffLayout({ children }: { children: React.ReactNode }) {
  const staff = await requireStaffContext();
  return <AppShell
    role={staff.role}
    email={staff.email}
    practiceName={staff.practiceName}
    tenantSlug={staff.tenantSlug}
    membershipCount={staff.memberships.length}
    platformRole={staff.platformRole}
  >{children}</AppShell>;
}
