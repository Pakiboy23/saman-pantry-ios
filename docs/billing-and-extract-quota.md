# Billing and extract quota

Source of truth for Samaan Pro and recipe-extract limits. Copy and counters
live in `FreeLimits` and `extract-recipe`. Do not take prices or gates from
the remote RevenueCat paywall.

## Intent

Free users can try voice/link extract. Pro pays for **unlimited extracts**
and the right to **start a family cookbook**. Pantry items and shopping
lists are unlimited for everyone. The public community book is free to
read and is not a Pro unlock. Joining a family is free.

This replaced the 1.2-era gates (30 pantry items, extra Lists-tab list, and
"Pro does not lift the 5/day extract cap"). Those claims are false on `main`.

## Who is metered

| Account | Cap | Reset |
|---------|-----|-------|
| Created before **2026-10-12 00:00:00 UTC** (`user_accounts.grandfathered`) | 5 extracts | Rolling 24h |
| Newer free accounts | 5 extracts | Lifetime (no daily reset) |
| `Saman Pro` entitlement | Uncapped | n/a |

Cutoff and reservation are in migration
`011_billing_grandfathered_and_quota.sql`. The Edge Function skips the RPC
for an active Pro subscriber and does **not** write `recipe_extraction_events`
for them (a later downgrade must not inherit Pro usage).

`create_family` uses the same cache: `user_accounts.is_pro OR grandfathered`.
See [`family-cookbooks.md`](./family-cookbooks.md).

## Request path

```
RecipeCaptureView
  → RecipeExtractionService (user JWT, never the anon key as Bearer)
    → extract-recipe
        1. lookupProEntitlement (RevenueCat secret, 2.5s timeout)
        2. if inactive: reserve_recipe_extraction (advisory lock + count + insert)
        3. fetch URL / call Anthropic
```

The capture screen does **not** refuse locally from `ExtractionQuotaService`.
402 from the server is authoritative so a returning Pro user can still extract
while RevenueCat identity is binding.

On 402 the client presents `SamaanPaywallView(trigger: .extractionLimit)`.
The counter (`my_extraction_quota_status` RPC → `ExtractionQuotaService`) is
display only. Pro hides it.

## HTTP outcomes

| Status | `code` | Client |
|--------|--------|--------|
| 402 | `quota_exceeded` (+ `grandfathered`) | Open the Pro paywall |
| 503 | `entitlement_unavailable` | Alert "Could not verify subscription. Try again." **Not** a paywall. Quota is not reserved. |
| 401 | — | Re-auth, then retry |
| 422 | `instagram_caption_unavailable`, `url_not_allowed`, `url_fetch_failed`, `no_recipe_text` | Alert. No slot consumed |

A transcript that reaches the model consumes a slot even when the provider
fails. A URL that returns a complete schema.org Recipe, or that is sent to
the model, consumes one. Failed URL fetches do not.

## RevenueCat identity

`Purchases.configure` runs anonymous at launch (`SamaanApp`). After the
session is known, `PurchaseSessionBinding` decides:

| Session | RevenueCat | Action |
|---------|------------|--------|
| Signed in | any | `Purchases.logIn` with the **lowercased** Supabase user UUID |
| Signed out | identified leftover | `Purchases.logOut` (clears local `isPro`) |
| Signed out | already anonymous | leave alone (guest Pro purchase must survive) |
| `-UITesting` / screenshots | any | ignore |

Guest Pro on an anonymous RC user is kept on purpose. Logging that identity
out would drop the purchase until Restore.

`revenuecat-sync` (user JWT, verify_jwt **on**) POSTs after a successful
`logIn` and when customer info shows active Pro — at most once per user
per process. It writes `user_accounts.is_pro` from RevenueCat v2 using
**`REVENUECAT_SECRET_KEY`** (not the v1 key). Entitlement lookup id is
`entlec857d8f70` ("Saman Pro"). Project `proje8d554d5`.

`revenuecat-webhook` (verify_jwt **false**) is the server-side path.
Authorization: `Bearer` matching `REVENUECAT_WEBHOOK_AUTH`. It updates
the same `is_pro` / `pro_updated_at` columns. Fallback subscriber lookup
uses **`REVENUECAT_SECRET_API_KEY`** (v1). A test event with no matching
row returns 200 `{ matched: 0 }` so RevenueCat does not retry.

Those two secret names are different on purpose. Mix them up and sync
500s (`not_configured`) while extract-recipe still verifies Pro.

On `main`, the webhook does **not** ignore sandbox events. Draft
[#78](https://github.com/Pakiboy23/saman-pantry-ios/pull/78) would skip
non-PRODUCTION and revoke TRANSFER donors. Do not treat that as shipped.

## Pro verification in extract-recipe

`lookupProEntitlement` needs `REVENUECAT_SECRET_API_KEY` on the function.

- Secret **unset**: everyone is treated as free (never silently uncapped).
- HTTP 404 subscriber: free.
- Timeout / other non-2xx: `unknown` → 503, no meter write.

Entitlement id is `Saman Pro`, byte-for-byte with the RevenueCat dashboard
and `PurchaseService.proEntitlementID`.

## Prices and products

Live paywall cards use `Package.storeProduct.localizedPriceString` from the
RevenueCat offering. Only `.monthly` and `.annual` packages are shown.
`FreeLimits` `$7.99 / month` and `$59.99 / year` are StoreKit / screenshot
fixtures only (`Saman.storekit`: `saman.pro.monthly`, `saman.pro.yearly`).
There is no lifetime SKU in the fixture or in paywall copy.

Do not "fix" live App Store Connect product ids from the fixture file. The
app reads whatever the current offering returns.

Paywall bullets are source-controlled in `FreeLimits.proBenefits` (unlimited
extracts, start family cookbooks, keep rescued recipes). The remote
RevenueCat paywall still has a retired grocery-delivery claim — do not load
feature copy from it.

## Onboarding (first launch)

`RootView` shows `OnboardingView` until `AppStorage` key
`samaan.hasCompletedOnboarding` is true. Three pages, then the existing tab
shell. Guest browse is unchanged: after onboarding, an unsigned launch still
reaches Home / Pantry / Lists / Recipes. Sign-in is still only for Sync now,
Extract Recipe, family-book opt-in, family cookbooks, and Delete account.

`-UITesting` / screenshot launches force the completed flag so seeded scenes
stay reachable.

## Deploy order

1. Apply `011_billing_grandfathered_and_quota.sql` in prod (owner).
2. Set `REVENUECAT_SECRET_API_KEY` if Pro should skip the extract quota.
3. `supabase functions deploy extract-recipe` (owner).
4. For family create to trust `is_pro`: set `REVENUECAT_SECRET_KEY`, deploy
   `revenuecat-sync`, then the webhook steps in
   [`family-books-go-steps.md`](./family-books-go-steps.md).

Deploying extract-recipe before 011 makes every extract 500. Leaving the
v1 secret unset meters Pro users as free. Agents do not apply SQL or deploy.

## Tests

```sh
deno test --allow-env supabase/functions/extract-recipe/
python3 supabase/tests/recipe_extraction_quota_test.py
```

iOS: `FreeLimitsTests` in `SamanTests/SamanTests.swift`.
