import { assertEquals } from "jsr:@std/assert@1";
import {
  candidateUserIDs,
  isProductionEvent,
  proFromEvent,
  proStateFromEvent,
} from "./events.ts";

const uid = "0B6A1C2D-3E4F-4A5B-8C6D-7E8F9A0B1C2D";
const donor = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const recipient = "ffffffff-bbbb-4ccc-8ddd-eeeeeeeeeeee";

Deno.test("candidate ids keep only Supabase UUIDs, lowercased, with aliases", () => {
  assertEquals(
    candidateUserIDs({ app_user_id: "$RCAnonymousID:abc", aliases: [uid, "$RCAnonymousID:abc"] }),
    [uid.toLowerCase()],
  );
});

Deno.test("candidate ids include TRANSFER donors so their Pro cache can be revoked", () => {
  assertEquals(
    candidateUserIDs({
      type: "TRANSFER",
      app_user_id: recipient,
      transferred_to: [recipient],
      transferred_from: [donor, "$RCAnonymousID:old"],
    }).sort(),
    [donor, recipient],
  );
});

Deno.test("sandbox and missing environment must not write production is_pro", () => {
  assertEquals(isProductionEvent({ environment: "PRODUCTION" }), true);
  assertEquals(isProductionEvent({ environment: "SANDBOX" }), false);
  assertEquals(isProductionEvent({}), false);
});

Deno.test("purchase of Saman Pro grants, expiration revokes, cancellation re-checks", () => {
  assertEquals(proFromEvent({ type: "INITIAL_PURCHASE", entitlement_ids: ["Saman Pro"], expiration_at_ms: Date.now() + 1e6 }), true);
  assertEquals(proFromEvent({ type: "NON_RENEWING_PURCHASE", entitlement_ids: ["Saman Pro"], expiration_at_ms: null }), true);
  assertEquals(proFromEvent({ type: "EXPIRATION", entitlement_ids: ["Saman Pro"] }), false);
  assertEquals(proFromEvent({ type: "CANCELLATION", entitlement_ids: ["Saman Pro"] }), null);
  assertEquals(proFromEvent({ type: "INITIAL_PURCHASE", entitlement_ids: ["Other"] }), null);
});

Deno.test("TRANSFER revokes the donor without a RevenueCat lookup", () => {
  const event = {
    type: "TRANSFER",
    transferred_from: [donor],
    transferred_to: [recipient],
  };
  assertEquals(proStateFromEvent(event, donor), false);
  assertEquals(proStateFromEvent(event, recipient), null);
  assertEquals(proStateFromEvent(event, uid), null);
});
