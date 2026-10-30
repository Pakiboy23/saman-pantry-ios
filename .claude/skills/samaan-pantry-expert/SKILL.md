---
name: samaan-pantry-expert
description: Expert for Samaan Pantry (Pakiboy23/saman-pantry-ios), a native iOS pantry for one desi kitchen. Use for SwiftUI, SwiftData, Supabase sync, recipe capture (recording, audio file, link, paste), the public family recipe book, private family cookbooks, Samaan Pro, or App Store release work. THESIS.md wins product arguments.
---

# Samaan Pantry expert

Native iOS. SwiftUI + SwiftData + Supabase (`mcknboqvblbonmaebmjg`) + RevenueCat. Thesis: one person, one desi kitchen, one loop: low → list → shop → bought → pantry updates. THESIS.md wins on product questions.

Not a meal planner, not a recipe discovery app, no household sharing (see the THESIS gates). The public community book and private family cookbooks are intentional and are not household mode.

## Names

- Product: **Samaan Pantry**. Paid tier: **Samaan Pro**. Use these in all user-facing copy.
- Single-a identifiers stay as they are: bundle id `com.samanpantry.Saman`, domain `samanpantry.com`, Xcode target/scheme `Saman`, RevenueCat entitlement `Saman Pro`.
- Legal entity: **Saman Technologies LLC dba Samaan Technologies**.
- No em dashes in app-facing copy (App Store text, in-app strings, paywall).

## Current state (30 Oct 2026, verified against `main`)

**App Store.** Last verified live is **Samaan Pantry 1.3 (build 133)**, released 5 Oct 2026 (`788fafd`: recording, audio-file intake, public family recipe book). Earlier: 1.0 (89), 1.1 (106), 1.2 (119). Do not claim 1.5 or 1.6 is live unless App Store Connect says so.

**main is 1.6.** `MARKETING_VERSION = 1.6`. Train: #66 billing + onboarding, #67 1.5 bump, #68 community-book URL opt-in, #69 HeyCatch, #70 Samaan copy, #71 HeyCatch bind, #76 RevenueCat `logIn` with the Supabase user id, #74 private family cookbooks. Build numbers come from Xcode Cloud, not the repo. `CURRENT_PROJECT_VERSION` in the pbxproj (108 today) is **not** the App Store Connect build number.

**Xcode Cloud archives every branch.** The single `Default` workflow archives (App Store eligible) on any branch push, and each run uploads a TestFlight build. Put `[ci skip]` in the latest commit message for docs-only pushes. App Review submission is still a manual App Store Connect step; never submit without Haaris's explicit OK.

**Samaan Pro** (see `docs/billing-and-extract-quota.md`):
- Fixture / screenshot prices: Monthly $7.99, Yearly $59.99. No lifetime SKU in `Saman.storekit` or paywall copy.
- Live cards use the RevenueCat offering's `localizedPriceString`.
- Free plan: 5 extracts (grandfathered accounts created before 2026-10-12 UTC keep 5/day; newer free accounts get 5 lifetime) + unlimited pantry and lists + community-book read. Pro is **unlimited extracts** and can **start a family cookbook**. Joining a family is free.
- 402 `quota_exceeded` opens the Pro paywall. 503 `entitlement_unavailable` is retry, not an upsell.
- Pro is uncapped in `extract-recipe` only when `REVENUECAT_SECRET_API_KEY` is set.
- After sign-in, `Purchases.logIn` uses the lowercased Supabase user UUID. `revenuecat-sync` (JWT, `REVENUECAT_SECRET_KEY`) and `revenuecat-webhook` (`REVENUECAT_WEBHOOK_AUTH` + v1 `REVENUECAT_SECRET_API_KEY`) write `user_accounts.is_pro`. Those two secret names are different.

**Onboarding.** First launch shows `OnboardingView` until `samaan.hasCompletedOnboarding`. Then the tab shell. Guest browse still ships: unsigned launch reaches Home / Pantry / Lists / Recipes on local SwiftData. Sign-in is asked for only on Sync now, Extract Recipe, community-book opt-in, family cookbooks, and Delete account. `-UITesting` skips onboarding. Do not restore a login wall.

**Recipe capture.** Four intakes: record, choose an audio file, paste a link (YouTube, Instagram, recipe sites), or paste text.
- Recording and audio files are transcribed **on device** (`RecipeAudioTranscriber`, `requiresOnDeviceRecognition = true`). Audio never leaves the phone. The recognizer follows the phone's language setting; Apple's on-device recognition covers Hindi but not Urdu or Punjabi, so desi words may come out spelled by ear.
- **Extraction runs server-side** in the `extract-recipe` Edge Function (Anthropic) with the user JWT. Quota is the table above (`011_billing_grandfathered_and_quota.sql`).
- Transcript saves publish a public card to the **community** book. URL extracts stay private unless the owner opts that recipe in (`share_in_family_book` / `012_recipe_book_url_opt_in.sql`). A shared link card shows the source link and attribution.

**Private family cookbooks** (#74). Recipes tab **Families** shelf. Pro or grandfathered to create; join is free. Invite: `https://www.samanpantry.com/join/<token>` or an 8-character code. Snapshots never include `raw_transcript`. Architecture: `docs/family-cookbooks.md`. Owner apply/deploy: `docs/family-books-go-steps.md`. Family SQL and the webhook are on `main` and are **not** live until Haaris applies them.

**Analytics.** Dual sink: anonymous Supabase `events` row + HeyCatch (PostHog iOS SDK). `HeyCatch.bind` identifies only a signed-in Supabase user id (#71). No recipe text or personal content as properties. Details: `docs/analytics.md`. Tests / previews / screenshots never start HeyCatch.

**Supabase (repo vs last verified live).**
- Last verified live `extract-recipe` is **version 9** (7 Oct 2026, `2632437`). #63 (meta/caption scan) and #66 (billing) are on `main` and are **not** live until `supabase functions deploy extract-recipe` after migration 011.
- `delete-account` last verified live is version 3.
- Migrations 001 through 009 were applied by 6 Oct 2026. **011, 012, and the 20261024 family-books pair are on `main`; owner applies them.** Deploying #66's function before 011 makes every extract 500.
- `revenuecat-webhook` and `revenuecat-sync` exist in the repo and are not live until deployed.
- Agents do not deploy or run production SQL.

**Legal URLs** `samanpantry.com/privacy` and `/support` are live and in the binary (Settings, Auth, paywall). Update the hosted privacy page from `docs/launch/legal-and-privacy.md` before shipping HeyCatch / family cookbooks.

## Non-negotiables (from THESIS.md)

- Mark bought must restock pantry. No lying to the user.
- Pantry and shopping list are one loop.
- No feature unless it advances the core loop.
- The app never stops feeling like a desi product (Saag / Atta / Kohl, Cormorant + Noto Nastaliq Urdu).
- Household sharing stays off until 500 WAU + 30% asking + sync stable.

## Landmines

- Anon key in `Config.swift` is expected (RLS). Service role is not.
- Recipe AI goes through `Config.recipeExtractionEndpoint` with the **user JWT**, never the anon key as Bearer, never Anthropic from the binary.
- Do not claim the recipe extraction happens on the phone. Only transcription does.
- Do not say Pro leaves extract capped, or that free users are limited to 30 pantry items / extra lists. Those 1.2 claims are dead.
- Do not locally refuse extract from the quota RPC. 402 is the gate; 503 is not a paywall.
- Without `REVENUECAT_SECRET_API_KEY`, Pro subscribers are metered as free.
- `REVENUECAT_SECRET_API_KEY` (v1, extract-recipe + webhook lookup) is not `REVENUECAT_SECRET_KEY` (v2, revenuecat-sync).
- Account deletion goes through `delete-account` with the user JWT. Family ownership hands off via `handoff_families_on_user_delete`.
- Deletes go through `AppEnvironment.deleteRecord` so a tombstone is queued. Bare `context.delete` resurrects the row on the next pull.
- The app target is a synchronized Xcode group. Every `.swift` under `Saman/` compiles with no pbxproj entry, so an unreferenced file still ships. Delete dead code, do not park it.
- Deleted and staying deleted: Prices, `ReorderView` / `ReorderItemRow` / `RestockSheet`, `PantryListView` / `AddPantryView`. The live loop is item detail → list → mark bought. InventoryView is the pantry surface.
- Scanner is a data-entry method inside Add Item, not a destination.
- Password recovery: `resetPasswordForEmail` uses `redirectTo: samaan://auth-callback`. Do **not** treat `.passwordRecovery` as sign-out.
- RevenueCat entitlement id is `Saman Pro`, byte-for-byte with the dashboard. Do not "fix" it.
- Paywall bullets are source-controlled (`FreeLimits`). The remote RevenueCat paywall copy still has a retired grocery-delivery claim; do not load feature copy from it.
- HeyCatch: `bind` then `releaseQueuedEvents`. Do not call `identify` / `reset` from feature code. Do not add event properties. Do not identify guests.
- Family invite links use **www**.samanpantry.com. Apex AASA will not follow the 307.
- `saveCopy()` on a family recipe with no `sourceUrl` currently uses `sourceKind: .transcript` and can publish to Community. Draft #79; not shipped.
- `-UITesting` is a screenshot seed path, not a substitute for guest browse.

## Owner console: confirm, don't assume

These live outside the repo. Ask Haaris or check the console before stating either way:

- Old Anthropic key revoked in the Anthropic console.
- Pre-confirmed App Review demo account exists and still signs in.
- `samaan://auth-callback` is in Supabase Auth → URL Configuration → Redirect URLs.
- Production has migrations 011, 012, and family-books, plus `REVENUECAT_SECRET_API_KEY`, `REVENUECAT_SECRET_KEY`, `REVENUECAT_WEBHOOK_AUTH`, and the matching function deploys.

## Do not

- Submit to App Review, release a version, or edit App Store Connect without Haaris's explicit OK.
- Deploy Edge Functions or run production SQL without Haaris's OK.
- Grow recipe CRUD into a meal planner or discovery cookbook.
- Add household sharing "because the models already have it." Private family cookbooks are not household mode.
- Ship "Alert me when below" without a real notification.
- Restore ReorderView or a mandatory-account splash.
- Push code branches casually: every push archives and uploads a TestFlight build.

## Next repo work (order)

1. Owner applies 011 + 012, sets the RevenueCat v1 secret if Pro should be uncapped, and deploys `extract-recipe`.
2. Owner follows `docs/family-books-go-steps.md` (family SQL, webhook, Associated Domains / AASA, App Privacy).
3. Update the hosted privacy page for HeyCatch and family cookbooks before a 1.6 submit.
4. Then, with Haaris's OK, pick a 1.6 TestFlight build for App Review.
5. Household mode only after the THESIS gates.

Open drafts, not shipped: #78 (sandbox webhook + TRANSFER donors), #79 (keep family copies out of Community).
