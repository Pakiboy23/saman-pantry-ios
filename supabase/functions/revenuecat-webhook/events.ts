// Pure event parsing for revenuecat-webhook. No I/O, so tests can import it.
export const entitlementID = "Saman Pro";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type RevenueCatEvent = {
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  transferred_to?: string[];
  transferred_from?: string[];
  entitlement_ids?: string[] | null;
  expiration_at_ms?: number | null;
  environment?: string;
};

export function candidateUserIDs(event: RevenueCatEvent): string[] {
  const ids = [
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
    ...(event.transferred_to ?? []),
    ...(event.transferred_from ?? []),
  ];
  return [...new Set(ids.filter((id): id is string => !!id && uuidPattern.test(id)).map((id) => id.toLowerCase()))];
}

// null = this event does not decide Pro for this user; re-check with the REST API.
// A transfer takes entitlements from transferred_from, so that account is not Pro
// even when the subscriber lookup is stale or unavailable.
export function proForUser(event: RevenueCatEvent, userID: string, now = Date.now()): boolean | null {
  if ((event.type ?? "") === "TRANSFER") {
    const id = userID.toLowerCase();
    const from = (event.transferred_from ?? []).map((value) => value.toLowerCase());
    const to = (event.transferred_to ?? []).map((value) => value.toLowerCase());
    if (from.includes(id) && !to.includes(id)) return false;
  }
  return proFromEvent(event, now);
}

/** null = this event says nothing about Pro; re-check with the REST API. */
export function proFromEvent(event: RevenueCatEvent, now = Date.now()): boolean | null {
  const grants = ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "NON_RENEWING_PURCHASE", "PRODUCT_CHANGE", "SUBSCRIPTION_EXTENDED", "TEMPORARY_ENTITLEMENT_GRANT"];
  const type = event.type ?? "";
  const mentionsPro = (event.entitlement_ids ?? []).includes(entitlementID);
  if (type === "EXPIRATION" && mentionsPro) return false;
  if (grants.includes(type) && mentionsPro) {
    return event.expiration_at_ms == null || event.expiration_at_ms > now;
  }
  // CANCELLATION keeps access until EXPIRATION. BILLING_ISSUE re-checks.
  // TRANSFER re-checks the destination; proForUser revokes the source.
  return null;
}

