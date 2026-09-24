import { FinishRecovery } from "@/components/onboarding/FinishRecovery";

export default async function FinishRecoveryPage({ searchParams }: { searchParams: Promise<{ invite?: string }> }) {
  const { invite } = await searchParams;
  const inviteId = /^[0-9a-f-]{36}$/i.test(invite || "") ? invite || "" : "";
  return <FinishRecovery inviteId={inviteId} />;
}
