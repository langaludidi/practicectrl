import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { ACTIVE_PRACTICE_COOKIE } from "@/lib/auth/server";

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return NextResponse.json({ error: "Authentication required." }, { status: 401 });

  const body = await request.json().catch(() => ({}));
  const practiceId = String(body?.practiceId || "");
  if (!/^[0-9a-f-]{36}$/i.test(practiceId)) return NextResponse.json({ error: "Invalid practice." }, { status: 400 });

  const { data: membership, error: membershipError } = await supabase
    .from("practice_staff_member")
    .select("practice_id,practice:practice!inner(id,active)")
    .eq("user_id", userData.user.id)
    .eq("practice_id", practiceId)
    .eq("active", true)
    .eq("practice.active", true)
    .maybeSingle();

  if (membershipError || !membership) return NextResponse.json({ error: "You do not have active access to this practice." }, { status: 403 });

  const { error: preferenceError } = await supabase.from("user_practice_preference").upsert({
    user_id: userData.user.id,
    last_practice_id: practiceId,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (preferenceError) return NextResponse.json({ error: "Could not save the selected practice." }, { status: 500 });

  const { data: aal, error: aalError } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aalError) return NextResponse.json({ error: "Could not verify security status." }, { status: 500 });

  const cookieStore = await cookies();
  cookieStore.set(ACTIVE_PRACTICE_COOKIE, practiceId, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 365,
  });
  return NextResponse.json({ ok: true, next: aal.currentLevel === "aal2" ? "/dashboard" : "/mfa" });
}
