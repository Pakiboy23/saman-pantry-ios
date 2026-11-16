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

### Audio route (live since version 19, 2026-11-16)

`multipart/form-data` with one part named `audio`. The server transcribes it,
then runs the same transcript extraction. Old clients sending JSON are
unaffected. Spec: [`docs/server-transcription-spec.md`](../../docs/server-transcription-spec.md).

- Types: `audio/mp4`, `audio/m4a`, `audio/x-m4a`, `audio/aac`, `audio/mpeg`, `audio/wav` (parameters such as `; codecs=` are ignored). Others: **415** `audio_unsupported_type`.
- Body cap 12 MiB (`12 * 1024 * 1024`). Larger: **413** `audio_too_large`. Checked from `Content-Length` and again while streaming.
- Missing or empty `audio` part, or an unparseable form: **400** `audio_missing`.
- Order: JWT → type/size → quota slot → transcription → extraction. No slot means no transcription call.
- Transcription error, timeout (60 s), or unreadable reply: slot released, **502** `transcription_failed`.
- Transcript under 20 characters after trimming: slot released, **422** `audio_no_speech` with the "I only caught part of that" copy.
- After a transcript reaches the model, the text rule applies: model failures keep the slot.
- Success adds `transcript` to the usual `{ recipe, raw_json }`. The client stores it as `rawTranscript`. Model failures on this route (`502`, `422 no_recipe_text`) also return `transcript` so the client can offer an edit-and-retry without recording again.
- Audio is forwarded to the provider as a Blob. It is never stored. Logs (`extract_recipe_transcription`) carry provider, model, status, byte count, type, timing, transcript length, and language code. Never audio or text.

Provider code is in `transcribe.ts`. The desi vocabulary in `vocabulary.ts` feeds both prompt rule 3 and the optional keyterms.

### Prompts and the recording test set

Prompts live in `prompts.ts`. The speech prompt (`systemPrompt`, used for `{ transcript }` and audio) adds rules 4 to 6 for speech-recognition input: repair a misheard ingredient only when context supports it and say so in `notes`, never repair `original_phrase`, do not double ingredients for repeated phrases, and leave unrelated personal talk out of the recipe. The page prompt has no speech rules. Both prompts keep alternatives ("lemon juice or vinegar") as one ingredient so the shopping list does not get both.

Any prompt change must pass the private recording test set before it merges:

```sh
ELEVENLABS_API_KEY=... ANTHROPIC_API_KEY=... \
deno run --allow-env --allow-read --allow-net scripts/recipe-eval.ts --manifest ~/samaan-eval/manifest.json
```

The script runs this checkout's transcription adapter and prompt against the providers directly, so it tests a change before deploy. Manifest schema: `scripts/recipe-eval.schema.json`. Cases can point at a recording or at a plain-text transcript (old on-device transcripts are useful regression inputs). The script refuses any manifest, recording, or transcript path inside the repo.

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
# Audio route. Required for multipart requests only. The function also reads
# the lowercase name `elevenlabs_api_key` as a fallback.
supabase secrets set ELEVENLABS_API_KEY=<elevenlabs-key>
# Optional overrides. Defaults: elevenlabs, scribe_v2, keyterms off.
supabase secrets set TRANSCRIBE_PROVIDER=elevenlabs
supabase secrets set ELEVENLABS_STT_MODEL=scribe_v2
# Keyterms cost about 20% more. Leave off unless the recording test set shows a gain.
supabase secrets set TRANSCRIBE_KEYTERMS=false
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically. Do not put `YOUTUBE_API_KEY` in the app.

### Tests

```sh
deno test --allow-env supabase/functions/extract-recipe/
# Eval script unit tests (no network, no recordings).
deno test --allow-read --allow-write --allow-env scripts/
# Real concurrency/RLS checks in an isolated temporary PostgreSQL cluster.
# Requires PostgreSQL 17 (initdb, pg_ctl, psql) and uuid-ossp; run as non-root.
python3 supabase/tests/recipe_extraction_quota_test.py
```

### Deploy

Owner approves every deploy. Live is version 21 (2026-11-16): billing,
URL extraction, the audio route, the speech prompt rules, and alternatives
as one ingredient, matching `main` at #85. Migrations
011, 012, and the family-books pair are applied in prod.

```sh
supabase functions deploy extract-recipe
```

Files in this function: `index.ts` (HTTP, auth, quota, audio route, model call), `prompts.ts` (extraction prompts), `recipe_source.ts` (URL classification, fetch, JSON-LD), `transcribe.ts` (speech-to-text provider adapter), and `vocabulary.ts` (desi ingredient map shared by the prompts and keyterms). `*_test.ts` files are tests only; they are not the entrypoint.

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
Family cookbooks hand off ownership first (`handoff_families_on_user_delete`).

## `revenuecat-webhook`

RevenueCat → `user_accounts.is_pro`. Deploy with **verify_jwt = false**
(`supabase/config.toml`). Auth is `Authorization: Bearer` matching
`REVENUECAT_WEBHOOK_AUTH` (timing-safe). Fallback subscriber lookup uses
`REVENUECAT_SECRET_API_KEY` (v1, same secret as extract-recipe).

A test event with no matching `user_accounts` row returns **200**
`{ ok: true, matched: 0 }` so RevenueCat does not retry. DB errors return 500.

On `main` (#78) it ignores non-PRODUCTION events and revokes Pro from TRANSFER donors. The live v9 (checked 2026-11-16) is a hand-deployed variant: it ignores sandbox events but not TRANSFER donors. Deploying the repo file replaces it.
Owner dashboard + deploy steps: [`docs/family-books-go-steps.md`](../../docs/family-books-go-steps.md).

```sh
supabase secrets set REVENUECAT_WEBHOOK_AUTH=<long random string>
supabase functions deploy revenuecat-webhook --no-verify-jwt
```

## `revenuecat-sync`

iOS POSTs this with the user JWT after `Purchases.logIn` and when customer
info shows active Pro (`PurchaseService.requestRevenueCatSync`). Deploy with
**verify_jwt on**. Writes `user_accounts.is_pro` from RevenueCat v2 using
**`REVENUECAT_SECRET_KEY`** (not the v1 API key). Project `proje8d554d5`,
entitlement id `entlec857d8f70` ("Saman Pro").

```sh
supabase secrets set REVENUECAT_SECRET_KEY=<revenuecat-v2-secret>
supabase functions deploy revenuecat-sync
```

401 invalid JWT, 502 RevenueCat down, 500 secret missing or update failed.
