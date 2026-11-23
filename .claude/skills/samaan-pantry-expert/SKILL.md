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

## Current state (20 Nov 2026, verified against `main`)

**App Store.** **Samaan Pantry 1.7 is live** (Haaris, 23 Nov 2026). Build number not recorded here. **1.8 (218) was submitted to App Review on 23 Nov 2026** (Community opt-in, #98). Earlier: 1.3 (133, 5 Oct 2026), 1.2 (119), 1.1 (106), 1.0 (89). Do not claim a later version is live unless App Store Connect says so.

**main is 1.8.** `MARKETING_VERSION = 1.8` (#98, merged 23 Nov 2026). 1.8 (218), built from the #98 branch, is in App Review. Train through 1.6 plus server transcription PRs A–D (#83/#84/#86/#92/#93), dark/tinted icons (#90), gallery review doc (#91), and `revenuecat-sync` on the v1 subscribers endpoint (#94). Build numbers come from Xcode Cloud, not the repo. `CURRENT_PROJECT_VERSION` in the pbxproj is **not** the App Store Connect build number.

**Xcode Cloud archives every branch.** The single `Default` workflow archives (App Store eligible) on any branch push, and each run uploads a TestFlight build. Put `[ci skip]` in the latest commit message for docs-only pushes. App Review submission is still a manual App Store Connect step; never submit without Haaris's explicit OK.

**Samaan Pro** (see `docs/billing-and-extract-quota.md`):
- Fixture / screenshot prices: Monthly $7.99, Yearly $59.99. No lifetime SKU in `Saman.storekit` or paywall copy.
- Live cards use the RevenueCat offering's `localizedPriceString`.
- Free plan: 5 extracts (grandfathered accounts created before 2026-10-12 UTC keep 5/day; newer free accounts get 5 lifetime) + unlimited pantry and lists + community-book read. Pro is **unlimited extracts** and can **start a family cookbook**. Joining a family is free.
- 402 `quota_exceeded` opens the Pro paywall. 503 `entitlement_unavailable` is retry, not an upsell.
- Pro is uncapped in `extract-recipe` only when `REVENUECAT_SECRET_API_KEY` is set.
- After sign-in, `Purchases.logIn` uses the lowercased Supabase user UUID. `revenuecat-sync` (JWT) and `revenuecat-webhook` (Bearer `REVENUECAT_WEBHOOK_AUTH`) both look up subscribers with v1 `REVENUECAT_SECRET_API_KEY` and write `user_accounts.is_pro`. #94 removed the unused v2 `REVENUECAT_SECRET_KEY` path. Live `revenuecat-sync` was still v8 (v2 path) on 2026-11-16; deploying the repo file is required.

**Onboarding.** First launch shows `OnboardingView` until `samaan.hasCompletedOnboarding`. Then the tab shell. Guest browse still ships: unsigned launch reaches Home / Pantry / Lists / Recipes on local SwiftData. Sign-in is asked for only on Sync now, Extract Recipe, community-book opt-in, family cookbooks, and Delete account. `-UITesting` skips onboarding. Do not restore a login wall.

**Recipe capture.** Four intakes: record, choose an audio file, paste a link (YouTube, Instagram, recipe sites), or paste text.
- **1.3 and earlier** transcribed on device with Apple's recognizer, which mangled desi words ("bhindi" -> "beans", "zeera" -> "0"). Live 1.7 uploads the recording instead.
- **On `main` (1.7 / PR C #86)** the app records mono AAC to a temp file (`RecipeAudioRecorder`, 10-minute cap, timer + level meter, no live text) and uploads it to `extract-recipe` (`RecipeExtractionService.extract(recording:)`), which transcribes with ElevenLabs. Picked files are re-encoded to AAC unless already AAC/MP3 under the cap. The file is kept until a recipe comes back so a failed upload can be retried, then deleted. The speech permission and `Speech` framework are gone. Consent key is `samaan.consent.recipeProcessing.v2` (everyone is asked again). In-app copy and PrivacyInfo audio landed with PR D (#92/#93).
- **Server transcription** (`docs/server-transcription-spec.md`, shipped). PR A (#83, live in v19+) added a multipart `audio` route to `extract-recipe` (ElevenLabs Scribe v2 via `transcribe.ts`, key `ELEVENLABS_API_KEY` with lowercase fallback). It takes the quota slot before transcribing and releases it on transcription failure or a transcript under 20 characters.
- **Prompts live in `prompts.ts`.** Any change must pass `scripts/recipe-eval.ts` against Haaris's private recording set before it merges. The script refuses paths inside the repo. Never commit recordings, real transcripts, or manifests.
- **Extraction runs server-side** in the `extract-recipe` Edge Function (Anthropic) with the user JWT. Quota is the table above (`011_billing_grandfathered_and_quota.sql`).
- **Community is opt-in for every recipe.** `20261123000000_community_opt_in.sql` is **applied in production** (23 Nov 2026, verified via connector): a recipe gets a public card only when the owner sets `share_in_family_book` ("Share to Community"). Cards are labeled with `family_label_for()` (display name, then email prefix), and `set_my_display_name` refreshes Community labels. The 6 cards that existed then were kept by backfilling the flag. The app toggle ships in 1.8 (#98, in App Review). Live 1.7 can't share spoken recipes and still labels them "in the family book". A shared link card shows the source link and attribution.

**Private family cookbooks** (#74). Recipes tab **Families** shelf. Pro or grandfathered to create; join is free. Invite: `https://www.samanpantry.com/join/<token>` or an 8-character code. Snapshots never include `raw_transcript`. Architecture: `docs/family-cookbooks.md`. Owner remaining steps: `docs/family-books-go-steps.md`. Family SQL is applied in prod (verified 2026-11-16). Live webhook is still the hand-deployed v9, not the #78 repo file.

**Analytics.** Dual sink: anonymous Supabase `events` row + HeyCatch (PostHog iOS SDK). `HeyCatch.bind` identifies only a signed-in Supabase user id (#71). No recipe text or personal content as properties. Details: `docs/analytics.md`. Tests / previews / screenshots never start HeyCatch.

**Supabase (verified 16 Nov 2026 through the Supabase connector; re-check before claiming).**
- `extract-recipe` **version 21** is live and byte-identical to `main` at #85: billing, URL extraction, the audio route, speech prompt rules 4-6, and alternatives as one ingredient. v20 (#84) and v19 (#83) are rollbacks.
- All migrations on `main` are applied, including 011, 012, and both family-books migrations. `20261123000000_community_opt_in` (PR #98) is also applied (23 Nov 2026).
- Also live (checked 2026-11-16): `delete-account` v11, `revenuecat-sync` v8 (pre-#94 v2 path), `revenuecat-webhook` v9, `asr-bakeoff` v4 (not in the repo).
- **Live `revenuecat-webhook` is a hand-deployed variant, not the repo file.** It ignores sandbox events but ignores `TRANSFER`, so it does not revoke donors the way #78 on `main` does.
- **Live `revenuecat-sync` v8 is not #94.** Repo code uses `REVENUECAT_SECRET_API_KEY` and `/v1/subscribers`. Deploy the repo file to pick that up.
- The connector cannot list secret names. Do not claim a secret is set; ask or have Haaris check.
- Agents deploy or run production SQL only with Haaris's explicit OK for that deploy. The Supabase connector can deploy; verify the deployed files against `main` afterwards.

**Legal URLs** `samanpantry.com/privacy` and `/support` are live and in the binary (Settings, Auth, paywall). Update the hosted privacy page from `docs/launch/legal-and-privacy.md` before shipping a 1.7 build (HeyCatch, family cookbooks, server transcription).

## Non-negotiables (from THESIS.md)

- Mark bought must restock pantry. No lying to the user.
- Pantry and shopping list are one loop.
- No feature unless it advances the core loop.
- The app never stops feeling like a desi product (Saag / Atta / Kohl, Cormorant + Noto Nastaliq Urdu).
- Household sharing stays off until 500 WAU + 30% asking + sync stable.

## Landmines

- Anon key in `Config.swift` is expected (RLS). Service role is not.
- Recipe AI goes through `Config.recipeExtractionEndpoint` with the **user JWT**, never the anon key as Bearer, never Anthropic from the binary.
- Do not claim the recipe extraction happens on the phone. Live 1.7 and `main` upload the recording for server transcription. Do not say "audio never leaves the phone" for a 1.7 build.
- PR C (#86) and PR D (#92/#93) are both on `main`. Never submit a 1.7 build that has C without D.
- Audio route: never log audio bytes or transcript text, never store audio, never commit recordings or real transcripts. Size/type checks run before the quota; the slot runs before the paid STT call.
- Do not say Pro leaves extract capped, or that free users are limited to 30 pantry items / extra lists. Those 1.2 claims are dead.
- Do not locally refuse extract from the quota RPC. 402 is the gate; 503 is not a paywall.
- Without `REVENUECAT_SECRET_API_KEY`, Pro subscribers are metered as free.
- `REVENUECAT_SECRET_API_KEY` (v1) is what extract-recipe, revenuecat-sync (#94), and webhook lookup all use. Do not restore `REVENUECAT_SECRET_KEY`.
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
- Family `saveCopy()` is always a private `.url` copy (`ownedCopy()`, #79). Do not restore `.transcript` there — that auto-publishes to Community.
- `-UITesting` is a screenshot seed path, not a substitute for guest browse.

## Owner console: confirm, don't assume

These live outside the repo. Ask Haaris or check the console before stating either way:

- Old Anthropic key revoked in the Anthropic console.
- Pre-confirmed App Review demo account exists and still signs in.
- `samaan://auth-callback` is in Supabase Auth → URL Configuration → Redirect URLs.
- Production secrets `REVENUECAT_SECRET_API_KEY`, `REVENUECAT_WEBHOOK_AUTH`, and the ElevenLabs key name. (Migrations and function versions can be checked with the Supabase connector. `REVENUECAT_SECRET_KEY` is unused after #94.)

## Do not

- Submit to App Review, release a version, or edit App Store Connect without Haaris's explicit OK.
- Deploy Edge Functions or run production SQL without Haaris's OK.
- Grow recipe CRUD into a meal planner or discovery cookbook.
- Add household sharing "because the models already have it." Private family cookbooks are not household mode.
- Ship "Alert me when below" without a real notification.
- Restore ReorderView or a mandatory-account splash.
- Push code branches casually: every push archives and uploads a TestFlight build.

## Next repo work (order)

1. Owner: deploy repo `revenuecat-sync` (#94) if live is still v8.
2. Owner: decide whether to replace the hand-deployed webhook with the repo version (#78, TRANSFER donor revoke).
3. Confirm the hosted privacy page covers HeyCatch, family cookbooks, and server transcription (1.7 is live; not verified here).
4. 1.8 (218) is in App Review. Once approved, release it before the Product Hunt launch (Haaris's call).
5. Household mode only after the THESIS gates.

#78 (sandbox webhook + TRANSFER donors) and #79 (family copies stay out of Community) are on `main`. #78 is not what the live webhook runs. #94 is on `main` and is not confirmed deployed.
