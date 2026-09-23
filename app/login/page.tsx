import Image from "next/image";
import { SignInForm } from "@/components/SignInForm";

export default function LoginPage() {
  return <main className="min-h-screen bg-[#051a39] lg:grid lg:grid-cols-[minmax(320px,.85fr)_minmax(480px,1.15fr)]">
    <section className="flex min-h-[250px] flex-col justify-between border-b border-white/10 p-8 text-white lg:min-h-screen lg:border-b-0 lg:border-r lg:p-12">
      <div>
        <p className="text-xs font-semibold uppercase tracking-[.16em] text-[#64d9d8]">PracticeCtrl</p>
        <h1 className="mt-5 max-w-lg text-3xl font-semibold leading-tight text-white lg:text-4xl">Clinical work, coding and revenue in one governed workflow.</h1>
        <p className="mt-4 max-w-lg text-sm leading-6 text-white/68">Clinical Operations. Coding Intelligence. Revenue Integrity.</p>
      </div>
      <p className="mt-10 max-w-md text-xs leading-5 text-white/55">Access is restricted to authorised practice staff. Practice, role and workflow permissions are applied after sign-in.</p>
    </section>

    <section className="flex min-h-[calc(100vh-250px)] items-center bg-[#f6f8fa] px-5 py-10 sm:px-8 lg:min-h-screen lg:px-14">
      <div className="mx-auto w-full max-w-[480px]">
        <div className="mb-8 inline-flex rounded-lg border border-[#dce3ea] bg-white px-4 py-3">
          <Image src="/brand/practicectrl-primary-logo.png" alt="PracticeCtrl" width={2048} height={682} priority className="h-11 w-auto max-w-[280px] object-contain" />
        </div>
        <div className="rounded-lg border border-[#dce3ea] bg-white p-6 sm:p-8">
          <p className="text-xs font-semibold uppercase tracking-[.13em] text-[#64748b]">Secure staff access</p>
          <h2 className="mt-2 text-2xl font-semibold text-[#051a39]">Sign in to PracticeCtrl</h2>
          <p className="mb-7 mt-2 text-sm leading-6 text-[#526276]">Use your authorised practice account. You will choose the practice context after authentication when more than one is available.</p>
          <SignInForm />
        </div>
      </div>
    </section>
  </main>;
}
