# Supabase Edge Functions

## `extract-recipe`

The iOS app calls `https://<project-ref>.supabase.co/functions/v1/extract-recipe` instead of calling Anthropic directly. This keeps private AI provider credentials out of the app binary.

The caller must send the **user JWT** (`Authorization: Bearer <access_token>`). The anon key as Bearer is rejected.

Free-tier quota (migration `011_billing_grandfathered_and_quota.sql`). Full
client + deploy notes: [`docs/billing-and-extract-quota.md`](../../docs/billing-and-extract-quota.md).

- **Grandfathered** accounts (created before 2026-10-12): 5 extractions per rolling 24h
- **New free** accounts: 5 lifetime extractions
- **Pro** (`Saman Pro` entitlement): uncapped when `REVENUECAT_SECRET_API_KEY` is set
- RevenueCat lookup failures / timeouts return **503** `{ code: "entitlement_unavailable" }` and do **not** reserve free-tier quota

402 is `{ code: "quota_exceeded", grandfathered: bool }`. The iOS client opens the Pro paywall.

Body is `{ "transcript" }` and/or `{ "url" }`. A transcript that is only an http(s) link is read as a URL.

- **Text** — unchanged. The slot is consumed before the model call, including when the provider fails.
- **YouTube** (`watch`, `youtu.be`, `shorts`, also `embed` / `live`) — title and description. Uses the YouTube Data API v3 when `YOUTUBE_API_KEY` is set, otherwise the public watch page and oEmbed. If the description is not a recipe, captions are a best-effort fallback. The text then goes to the model.
- **Recipe pages** — fetch the HTML. A complete schema.org Recipe JSON-LD is returned without calling the model. Otherwise cleaned page text goes to the model.
- **Instagram** — best effort. If the caption cannot be read, **422** `{ code: "instagram_caption_unavailable" }` asks the user to paste the caption. That failure does not consume a slot.
- Other fetch failures (`url_not_allowed`, `url_fetch_failed`, `no_recipe_text`) do not consume a slot. A URL that returns a recipe, or that is sent to the model, consumes one.

Outbound fetches are http/https only, reject private and internal addresses (and DNS answers or redirects that point at them), time out, and cap the body size.

Requires migrations `004`, `009`, and `011` applied in prod before this deploy, or
every extract 500s. The service-role-only `reserve_recipe_extraction` RPC locks
admissions per user and counts/inserts in one transaction. Deploy the updated
function after migration 011.

### Required Supabase secrets

```sh
supabase secrets set ANTHROPIC_API_KEY=<rotated-production-key>
# Optional override; defaults to claude-sonnet-4-6
supabase secrets set ANTHROPIC_MODEL=claude-sonnet-4-6
# Optional. When set, YouTube links use Data API v3 videos.list (snippet).
# When unset, the function uses the public watch page. Captions are best-effort either way.
supabase secrets set YOUTUBE_API_KEY=<youtube-data-api-v3-key>
# Optional until new Pro products are live. When set, extract-recipe skips the
# free-tier quota for subscribers with the Saman Pro entitlement.
supabase secrets set REVENUECAT_SECRET_API_KEY=<revenuecat-secret-api-key>
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically. Do not put `YOUTUBE_API_KEY` in the app.

### Tests

```sh
deno test --allow-env supabase/functions/extract-recipe/
# Real concurrency/RLS checks in an isolated temporary PostgreSQL cluster.
# Requires PostgreSQL 17 (initdb, pg_ctl, psql) and uuid-ossp; run as non-root.
python3 supabase/tests/recipe_extraction_quota_test.py
```

### Deploy

Owner only, after migration 011 is applied in prod. Last verified live
function is version 9 (2026-10-07). The billing path on `main` is not live
until this runs:

```sh
supabase functions deploy extract-recipe
```

Files in this function: `index.ts` (HTTP, auth, quota, model) and `recipe_source.ts` (URL classification, fetch, JSON-LD). `recipe_source_test.ts` is tests only; it is not the entrypoint.

After deployment, revoke/rotate any Anthropic key that was previously committed or shipped in a client binary.

## `delete-account`

In-app account deletion, required by App Store Guideline 5.1.1(v). The iOS app
calls `https://<project-ref>.supabase.co/functions/v1/delete-account` with the
signed-in user's JWT. The function validates the token and deletes the auth user
with the service-role key; `ON DELETE CASCADE` foreign keys remove all owned rows.

### Required secrets

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected into Edge Functions
automatically — no manual secret setup is needed.

### Deploy

```sh
supabase functions deploy delete-account
```

Verify that every table's `user_id` foreign key is declared `on delete cascade`
(see `supabase/migrations/001_initial_schema.sql`) so deletion fully removes user data.
