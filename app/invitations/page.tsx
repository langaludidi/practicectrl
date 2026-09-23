import Link from "next/link";
import { redirect } from "next/navigation";
import { AcceptInvitePanel } from "@/components/onboarding/AcceptInvitePanel";
import { createClient } from "@/lib/supabase/server";

export default async function InvitationsPage() {
  const supabase = await createClient();
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) redirect("/login");

  const { data: invitations, error } = await supabase
    .from("practice_staff_invitation")
    .select("id,practice_id,email,role,status,expires_at,created_at,practice:practice(name,tenant_slug)")
    .eq("status", "pending")
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false });
  if (error) throw error;

  return <main className="mx-auto min-h-screen max-w-2xl px-5 py-12">
    <section className="rounded-3xl border border-stone-200 bg-stone-50 p-6 shadow-sm sm:p-8">
      <p className="text-xs font-bold uppercase tracking-[.2em] text-[#b84f45]">PracticeCtrl</p>
      <h1 className="mt-2 text-3xl font-semibold text-[#4a1f3e]">Practice invitations</h1>
      <p className="mt-2 text-sm text-stone-600">A single PracticeCtrl identity can belong to more than one practice. Each invitation adds a separate tenant membership and role.</p>
      <div className="mt-6 grid gap-4">
        {(invitations ?? []).map((invitation: any) => {
          const practice = Array.isArray(invitation.practice) ? invitation.practice[0] : invitation.practice;
          return <article key={invitation.id} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div><p className="font-semibold text-[#4a1f3e]">{practice?.name ?? "Practice invitation"}</p><p className="mt-1 text-xs text-stone-500">{practice?.tenant_slug ?? invitation.practice_id} · {String(invitation.role).replaceAll("_", " ")}</p></div>
              <span className="rounded-full bg-stone-100 px-2.5 py-1 text-xs text-stone-600">expires {new Date(invitation.expires_at).toLocaleString("en-ZA")}</span>
            </div>
            <AcceptInvitePanel inviteId={invitation.id}/>
          </article>;
        })}
        {!(invitations ?? []).length ? <div className="rounded-2xl border border-stone-200 bg-white p-5 text-sm text-stone-600">No active invitations are waiting for {auth.user.email ?? "this account"}.</div> : null}
      </div>
      <div className="mt-6"><Link href="/select-practice" className="text-sm font-medium text-[#4a1f3e] underline underline-offset-4">Back to practice selection</Link></div>
    </section>
  </main>;
}
