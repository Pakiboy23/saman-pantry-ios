// RevenueCat webhook: caches the `Saman Pro` entitlement in user_accounts.is_pro
// so SQL (create_family) can check Pro without calling RevenueCat.
//
// Deploy with verify_jwt = false (see config.toml). RevenueCat sends the
// Authorization header value set in its dashboard; it must equal the
// REVENUECAT_WEBHOOK_AUTH secret. Unmatched users are logged and get 200 so
// RevenueCat does not retry forever.
import { createClient } from "jsr:@supabase/supabase-js@2";

import { candidateUserIDs, entitlementID, proFromEvent, type RevenueCatEvent } from "./events.ts";

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function lookupPro(appUserId: string): Promise<boolean | null> {
  const secret = Deno.env.get("REVENUECAT_SECRET_API_KEY")?.trim();
  if (!secret) return null;
  const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
  if (res.status === 404) return false;
  if (!res.ok) return null;
  const body = await res.json() as { subscriber?: { entitlements?: Record<string, { expires_date?: string | null }> } };
  const ent = body.subscriber?.entitlements?.[entitlementID];
  if (!ent) return false;
  return ent.expires_date == null || Date.parse(ent.expires_date) > Date.now();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_AUTH")?.trim();
  const got = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!expected || !timingSafeEqual(got, expected)) {
    return new Response("unauthorized", { status: 401 });
  }

  let event: RevenueCatEvent;
  try {
    event = ((await req.json()) as { event?: RevenueCatEvent }).event ?? {};
  } catch {
    return new Response("bad json", { status: 400 });
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const ids = candidateUserIDs(event);
  if (ids.length === 0) {
    console.warn("revenuecat-webhook: no Supabase user id on event", event.type);
    return Response.json({ ok: true, matched: 0 });
  }

  let matched = 0;
  for (const id of ids) {
    const fromEvent = proFromEvent(event);
    const isPro = fromEvent ?? await lookupPro(id);
    if (isPro == null) {
      console.warn("revenuecat-webhook: could not resolve Pro state", event.type);
      continue;
    }
    const { data, error } = await supabase
      .from("user_accounts")
      .update({ is_pro: isPro, pro_updated_at: new Date().toISOString() })
      .eq("id", id)
      .select("id");
    if (error) {
      console.error("revenuecat-webhook: update failed", error.code);
      return new Response("db error", { status: 500 }); // RevenueCat retries
    }
    matched += data?.length ?? 0;
  }
  if (matched === 0) console.warn("revenuecat-webhook: no user_accounts row matched", event.type);
  return Response.json({ ok: true, matched });
});
