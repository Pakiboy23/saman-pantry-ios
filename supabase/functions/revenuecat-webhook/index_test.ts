import { assertEquals } from "jsr:@std/assert@1";
import { candidateUserIDs, proForUser, proFromEvent } from "./events.ts";

const uid = "0B6A1C2D-3E4F-4A5B-8C6D-7E8F9A0B1C2D";

Deno.test("candidate ids keep only Supabase UUIDs, lowercased, with aliases", () => {
  assertEquals(
    candidateUserIDs({ app_user_id: "$RCAnonymousID:abc", aliases: [uid, "$RCAnonymousID:abc"] }),
    [uid.toLowerCase()],
  );
});

Deno.test("transfer revokes the source account and re-checks the destination", () => {
  const from = "11111111-1111-4111-8111-111111111111";
  const to = "22222222-2222-4222-8222-222222222222";
  const event = { type: "TRANSFER", transferred_from: [from.toUpperCase()], transferred_to: [to] };
  assertEquals(candidateUserIDs(event).sort(), [from, to].sort());
  assertEquals(proForUser(event, from), false);
  assertEquals(proForUser(event, to), null);
});

Deno.test("purchase of Saman Pro grants, expiration revokes, cancellation re-checks", () => {
  assertEquals(proFromEvent({ type: "INITIAL_PURCHASE", entitlement_ids: ["Saman Pro"], expiration_at_ms: Date.now() + 1e6 }), true);
  assertEquals(proFromEvent({ type: "NON_RENEWING_PURCHASE", entitlement_ids: ["Saman Pro"], expiration_at_ms: null }), true);
  assertEquals(proFromEvent({ type: "EXPIRATION", entitlement_ids: ["Saman Pro"] }), false);
  assertEquals(proFromEvent({ type: "CANCELLATION", entitlement_ids: ["Saman Pro"] }), null);
  assertEquals(proFromEvent({ type: "INITIAL_PURCHASE", entitlement_ids: ["Other"] }), null);
});
