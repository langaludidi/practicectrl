import { SignInForm } from "@/components/SignInForm";
export default function LoginPage() {
  return <main className="grid min-h-screen place-items-center p-6"><section className="w-full max-w-md rounded-3xl border border-stone-200 bg-white p-8 shadow-sm">
    <p className="text-xs font-bold tracking-[.2em] text-[#e5533d]">PRACTICECTRL</p>
    <h1 className="mt-3 text-3xl font-semibold text-[#4a1f3e]">Clinical operations</h1>
    <p className="mb-7 mt-2 text-sm text-stone-600">Sign in once, then choose the practice you are authorised to work in.</p>
    <SignInForm />
    <p className="mt-6 text-xs leading-5 text-stone-500">Access is restricted to authorised practice staff. Each practice has independent roles, data, integrations and workflow state.</p>
  </section></main>;
}
