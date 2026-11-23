// revenuecat-sync: sets user_accounts.is_pro for the signed-in caller
// from RevenueCat's live entitlement state. Deploy with verify_jwt on.
// Secret: REVENUECAT_SECRET_API_KEY (same key and v1 endpoint extract-recipe uses).
import { createClient } from "jsr:@supabase/supabase-js@2";

const RC_ENTITLEMENT = "Saman Pro"; // v1 keys entitlements by identifier

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const rcKey = Deno.env.get("REVENUECAT_SECRET_API_KEY");
  if (!rcKey) {
    console.error("not_configured: REVENUECAT_SECRET_API_KEY is missing");
    return Response.json({ error: "not_configured" }, { status: 500 });
  }

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) return Response.json({ error: "unauthorized" }, { status: 401 });
  const userId = userData.user.id.toLowerCase();

  const rcRes = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
    { headers: { Authorization: `Bearer ${rcKey}`, "Content-Type": "application/json" } },
  );
  let isPro = false;
  if (rcRes.status === 404) {
    isPro = false; // no RevenueCat customer under this ID yet
  } else if (!rcRes.ok) {
    console.error("revenuecat_error", rcRes.status);
    return Response.json({ error: "revenuecat_unavailable" }, { status: 502 });
  } else {
    const body = await rcRes.json() as {
      subscriber?: { entitlements?: Record<string, { expires_date?: string | null }> };
    };
    const ent = body.subscriber?.entitlements?.[RC_ENTITLEMENT];
    isPro = !!ent && (ent.expires_date == null || Date.parse(ent.expires_date) > Date.now());
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
