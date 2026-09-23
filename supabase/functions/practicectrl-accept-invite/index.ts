
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

function keys() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const publishableJson = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  const secretJson = Deno.env.get("SUPABASE_SECRET_KEYS");
  const publishable = publishableJson ? JSON.parse(publishableJson).default : Deno.env.get("SUPABASE_ANON_KEY");
  const secret = secretJson ? JSON.parse(secretJson).default : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishable || !secret) throw new Error("Supabase function environment is unavailable");
  return { url, publishable, secret };
}
function json(body: unknown, status = 200, origin?: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": origin || "null",
      "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
      "access-control-allow-methods": "POST, OPTIONS",
      "vary": "Origin",
    },
  });
}

Deno.serve(async (req) => {
  const { url, publishable, secret } = keys();
  const authHeader = req.headers.get("authorization") || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

  if (req.method === "OPTIONS") {
    const origin = req.headers.get("origin") || "";
    if (!origin) return json({ error: "Origin required." }, 403);
    const { data: origins } = await admin.from("practice_app_origin").select("origin").eq("active", true);
    if (!(origins || []).some((x:any) => x.origin === origin)) return json({ error: "Origin not allowed." }, 403);
    return json({ ok: true }, 200, origin);
  }
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
  if (!token) return json({ error: "Authentication required." }, 401);

  const userClient = createClient(url, publishable, {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user || !user.email) return json({ error: "Authenticated invitation session required." }, 401);

  const body = await req.json().catch(() => ({}));
  const inviteId = String(body?.inviteId || "");
  if (!/^[0-9a-f-]{36}$/i.test(inviteId)) return json({ error: "Invalid invitation." }, 400);

  const { data: invite, error: inviteError } = await admin
    .from("practice_staff_invitation")
    .select("practice_id")
    .eq("id", inviteId)
    .maybeSingle();

  if (inviteError || !invite) return json({ error: "Invitation not found." }, 404);

  const { data: appOrigin } = await admin.from("practice_app_origin")
    .select("origin")
    .eq("practice_id", invite.practice_id)
    .eq("environment","staging")
    .eq("active",true)
    .maybeSingle();
  const allowedOrigin = appOrigin?.origin || "";
  const requestOrigin = req.headers.get("origin") || "";
  if (!allowedOrigin) return json({ error: "PracticeCtrl staging origin is not configured." }, 503);
  if (requestOrigin && requestOrigin !== allowedOrigin) return json({ error: "Origin not allowed." }, 403, allowedOrigin);

  const { data: outcome, error: acceptError } = await admin.rpc("accept_practice_staff_invitation_v2", {
    p_invitation_id: inviteId,
    p_user_id: user.id,
    p_email: user.email,
  });

  if (acceptError) return json({ error: "Invitation acceptance failed." }, 500, allowedOrigin);
  if (!outcome?.ok) {
    const code = String(outcome?.code || "");
    const status = code === "expired" ? 410
      : code === "not_found" ? 404
      : code === "email_mismatch" || code === "identity_mismatch" ? 403
      : code === "not_active" ? 409
      : 400;
    return json({ error: outcome?.message || "Invitation acceptance failed." }, status, allowedOrigin);
  }

  return json({ ok: true, role: outcome.role }, 200, allowedOrigin);
});

