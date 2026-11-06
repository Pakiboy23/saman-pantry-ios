# Edge Functions & Account Deletion

This June spec is obsolete. Do not copy the old `recipe_usage` / `callerIsPro` snippets into a new function.

Live source of truth:

- [`docs/billing-and-extract-quota.md`](../billing-and-extract-quota.md) — grandfathered 5/day vs new-free 5 lifetime vs Pro uncapped. 402 opens the paywall; 503 does not. RevenueCat `logIn` + `revenuecat-sync` / webhook.
- [`docs/family-cookbooks.md`](../family-cookbooks.md) — private families. Account deletion hands off ownership via `handoff_families_on_user_delete`.
- [`supabase/functions/extract-recipe/`](../../supabase/functions/extract-recipe/) — user JWT, quota via `recipe_extraction_events` + `user_accounts` (not `recipe_usage`). Accepts a transcript or an http(s) link (YouTube, recipe page, best-effort Instagram). Client uses `Config.recipeExtractionEndpoint`.
- [`supabase/functions/delete-account/`](../../supabase/functions/delete-account/) — user JWT + service role. Client uses `Config.deleteAccountEndpoint`. No RevenueCat customer delete in-repo; sign-out runs `Purchases.logOut` when the session was identified.
- [`supabase/functions/revenuecat-webhook/`](../../supabase/functions/revenuecat-webhook/) and [`revenuecat-sync/`](../../supabase/functions/revenuecat-sync/) — write `user_accounts.is_pro`. Different secrets (v1 `REVENUECAT_SECRET_API_KEY` vs v2 `REVENUECAT_SECRET_KEY`).
- [`supabase/functions/README.md`](../../supabase/functions/README.md) — secrets and deploy commands.
- [`supabase/migrations/011_billing_grandfathered_and_quota.sql`](../../supabase/migrations/011_billing_grandfathered_and_quota.sql) — current reserve RPC. 004/009 are the older event table.

Owner still must apply pending migrations (011, 012, family-books) in prod and deploy the functions. Keep those blockers in `MEMORY.md` only.
