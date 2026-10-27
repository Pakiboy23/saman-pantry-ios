// revenuecat-sync: sets user_accounts.is_pro for the signed-in caller
// from RevenueCat's live entitlement state. Deploy with verify_jwt on.
// Secrets: REVENUECAT_SECRET_KEY (v2, read-only customer info).
import { createClient } from "jsr:@supabase/supabase-js@2";

const RC_PROJECT_ID = "proje8d554d5";
const RC_ENTITLEMENT_ID = "entlec857d8f70"; // "Saman Pro"

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const rcKey = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!rcKey) return Response.json({ error: "not_configured" }, { status: 500 });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) return Response.json({ error: "unauthorized" }, { status: 401 });
  const userId = userData.user.id.toLowerCase();

  const rcRes = await fetch(
    `https://api.revenuecat.com/v2/projects/${RC_PROJECT_ID}/customers/${encodeURIComponent(userId)}/active_entitlements`,
    { headers: { Authorization: `Bearer ${rcKey}` } },
  );
  let isPro = false;
  if (rcRes.status === 404) {
    isPro = false; // no RevenueCat customer under this ID yet
  } else if (!rcRes.ok) {
    console.error("revenuecat_error", rcRes.status);
    return Response.json({ error: "revenuecat_unavailable" }, { status: 502 });
  } else {
    const body = await rcRes.json();
    const items: Array<{ entitlement_id: string; expires_at: number | null }> = body.items ?? [];
    const now = Date.now();
    isPro = items.some((e) => e.entitlement_id === RC_ENTITLEMENT_ID && (e.expires_at == null || e.expires_at > now));
  }

  const { error: updErr } = await admin
    .from("user_accounts")
    .update({ is_pro: isPro, pro_updated_at: new Date().toISOString() })
    .eq("id", userId);
  if (updErr) {
    console.error("update_failed", updErr.message);
    return Response.json({ error: "update_failed" }, { status: 500 });
  }
  return Response.json({ is_pro: isPro });
});
