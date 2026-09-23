import { RecoveryForm } from "@/components/onboarding/RecoveryForm";

export default async function RecoverPage({searchParams}:{searchParams:Promise<{invite?:string}>}){
  const {invite}=await searchParams;
  const inviteId=/^[0-9a-f-]{36}$/i.test(invite||"")?invite||"":"";
  return <main className="mx-auto flex min-h-screen max-w-lg items-center px-5 py-12">
    <section className="w-full rounded-3xl border border-stone-200 bg-white p-7 shadow-sm">
      <p className="text-xs font-bold uppercase tracking-[.2em] text-[#067c80]">PracticeCtrl</p>
      <h1 className="mt-2 text-2xl font-semibold text-[#051a39]">Set up your account</h1>
      <p className="mt-2 text-sm text-stone-600">Request a secure link to set your password and continue your staff invitation.</p>
      <RecoveryForm inviteId={inviteId}/>
    </section>
  </main>;
}
