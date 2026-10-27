import { createClient } from "jsr:@supabase/supabase-js@2";

const ENTITLEMENT_ID = "entlec857d8f70";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const GRANT = new Set(["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "NON_RENEWING_PURCHASE", "PRODUCT_CHANGE", "SUBSCRIPTION_EXTENDED", "TEMPORARY_ENTITLEMENT_GRANT"]);
const REVOKE = new Set(["EXPIRATION"]);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_AUTH");
  if (!secret) return new Response("not configured", { status: 503 });
  const auth = req.headers.get("Authorization") ?? "";
  if (auth !== secret && auth !== `Bearer ${secret}`) return new Response("unauthorized", { status: 401 });

  let body: any;
  try { body = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const ev = body?.event;
  if (!ev?.type) return new Response("ok", { status: 200 });

  const ents: string[] = ev.entitlement_ids ?? (ev.entitlement_id ? [ev.entitlement_id] : []);
  if (ev.type !== "TRANSFER" && ents.length && !ents.includes(ENTITLEMENT_ID)) return new Response("ignored", { status: 200 });

  let isPro: boolean | null = null;
  if (GRANT.has(ev.type)) isPro = true;
  else if (REVOKE.has(ev.type)) isPro = false;
  if (isPro === null) return new Response("ignored", { status: 200 });

  const ids = [ev.app_user_id, ev.original_app_user_id, ...(ev.aliases ?? [])]
    .filter((x) => typeof x === "string").map((x: string) => x.toLowerCase()).filter((x) => UUID_RE.test(x));
  const uniq = [...new Set(ids)];
  if (!uniq.length) return new Response("no supabase user", { status: 200 });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await admin.from("user_accounts")
    .update({ is_pro: isPro, pro_updated_at: new Date().toISOString() }).in("id", uniq);
  if (error) { console.error("update failed", error.message); return new Response("db error", { status: 500 }); }
  return new Response("ok", { status: 200 });
});
