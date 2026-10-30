# Billing and extract quota

Source of truth for Samaan Pro and recipe-extract limits. Copy and counters
live in `FreeLimits` and `extract-recipe`. Do not take prices or gates from
the remote RevenueCat paywall.

## Intent

Free users can try voice/link extract. Pro pays for **unlimited extracts**.
Pantry items and shopping lists are unlimited for everyone. The public family
recipe book is free to read and is not a Pro unlock.

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

## Pro verification

`lookupProEntitlement` needs `REVENUECAT_SECRET_API_KEY` on the function.

- Secret **unset**: everyone is treated as free (never silently uncapped).
- HTTP 404 subscriber: free.
- Timeout / other non-2xx: `unknown` → 503, no meter write.

Entitlement id is `Saman Pro`, byte-for-byte with the RevenueCat dashboard.

## Prices and products

Live paywall cards use `Package.storeProduct.localizedPriceString` from the
RevenueCat offering. `FreeLimits` `$7.99 / month` and `$59.99 / year` are
StoreKit / screenshot fixtures only (`Saman.storekit`: `saman.pro.monthly`,
`saman.pro.yearly`). There is no lifetime SKU in the fixture or in paywall
copy.

Do not "fix" live App Store Connect product ids from the fixture file. The
app reads whatever the current offering returns.

Paywall bullets are source-controlled in `FreeLimits.proBenefits`. The remote
RevenueCat paywall still has a retired grocery-delivery claim — do not load
feature copy from it.

## Onboarding (first launch)

`RootView` shows `OnboardingView` until `AppStorage` key
`samaan.hasCompletedOnboarding` is true. Three pages, then the existing tab
shell. Guest browse is unchanged: after onboarding, an unsigned launch still
reaches Home / Pantry / Lists / Recipes. Sign-in is still only for Sync now,
Extract Recipe, family-book opt-in, and Delete account.

`-UITesting` / screenshot launches force the completed flag so seeded scenes
stay reachable.

## Deploy order

1. Apply `011_billing_grandfathered_and_quota.sql` in prod (owner).
2. Set `REVENUECAT_SECRET_API_KEY` if Pro should skip the quota.
3. `supabase functions deploy extract-recipe` (owner).

Deploying the function before 011 makes every extract 500. Leaving the secret
unset meters Pro users as free. Agents do not apply SQL or deploy.

## Tests

```sh
deno test --allow-env supabase/functions/extract-recipe/
python3 supabase/tests/recipe_extraction_quota_test.py
```

iOS: `FreeLimitsTests` in `SamanTests/SamanTests.swift`.
