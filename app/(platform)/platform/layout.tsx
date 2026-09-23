import { PlatformShell } from "@/components/PlatformShell";
import { requirePlatformContext } from "@/lib/auth/server";
export default async function PlatformLayout({ children }: { children: React.ReactNode }) {
  const platform=await requirePlatformContext();
  return <PlatformShell role={platform.role} email={platform.email}>{children}</PlatformShell>;
}
