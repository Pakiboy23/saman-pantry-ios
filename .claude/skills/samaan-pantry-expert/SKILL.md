---
name: samaan-pantry-expert
description: Expert for Samaan Pantry (Pakiboy23/saman-pantry-ios), a native iOS pantry for one desi kitchen. Use for SwiftUI, SwiftData, Supabase sync, recipe capture (recording, audio file, link, paste), the family recipe book, Samaan Pro, or App Store release work. THESIS.md wins product arguments.
---

# Samaan Pantry expert

Native iOS. SwiftUI + SwiftData + Supabase (`mcknboqvblbonmaebmjg`) + RevenueCat. Thesis: one person, one desi kitchen, one loop: low → list → shop → bought → pantry updates. THESIS.md wins on product questions.

Not a meal planner, not a recipe discovery app, no household sharing (see the THESIS gates). The public family recipe book is intentional and is not household mode.

## Names

- Product: **Samaan Pantry**. Paid tier: **Samaan Pro**. Use these in all user-facing copy.
- Single-a identifiers stay as they are: bundle id `com.samanpantry.Saman`, domain `samanpantry.com`, Xcode target/scheme `Saman`, RevenueCat entitlement `Saman Pro`.
- Legal entity: **Saman Technologies LLC dba Samaan Technologies**.
- No em dashes in app-facing copy (App Store text, in-app strings, paywall).

## Current state (8 Oct 2026, verified)

**App Store.** Live is **Samaan Pantry 1.3 (build 133)**, released 5 Oct 2026. Build 133 is `main` at `788fafd`, so 1.3 includes on-device recording, audio-file intake, and the family recipe book (#44, #46). Earlier releases: 1.0 (89), 1.1 (106), 1.2 (119). A **1.4** App Store version exists in App Store Connect as a metadata draft (Prepare for Submission, no build).

**main is 1.3.1.** `MARKETING_VERSION = 1.3.1` (#50). 1.3.1 carries the recording fix (#49, #60, #61), the stale-session sign-out fix (#59), and the Int-conversion crash fix (#56). TestFlight has 1.3.1 builds through 161 as of 7 Oct 2026. Build 158 is `main` at the #61 merge (`2632437`). 157, the last build handed to Haaris for testing, came from the #61 branch head, and 159 to 161 came from other non-main branches.

**Build numbers come from Xcode Cloud**, not the repo. `CURRENT_PROJECT_VERSION` in the pbxproj (107 today) is **not** the App Store Connect build number. Do not bump it to "fix" a build number and do not quote it as a TestFlight build.

**Xcode Cloud archives every branch.** The single `Default` workflow archives (App Store eligible) on any branch push, and each run uploads a TestFlight build. Put `[ci skip]` in the latest commit message for docs-only pushes. App Review submission is still a manual App Store Connect step; never submit without Haaris's explicit OK.

**Samaan Pro** (live since 1.2): Monthly $4.99, Yearly $39.99, Lifetime $79.99. Free plan: 30 pantry items and one extra list from the Lists tab (`FreeLimits`). Pro does **not** raise the extract quota. App Store Connect product ids are irregular (`.com.samanpantry.pro.monthly`, `com.Samanpantry.pro.yearly`, `com.samanpantry.pro.lifetime`); the app reads them through the RevenueCat offering. Do not "fix" them.

**Guest browse shipped (#20).** Unsigned launch reaches Home / Pantry / Lists / Recipes on local SwiftData. Sign-in is asked for only on Sync now, Extract Recipe, and Delete account. Do not restore a login wall.

**Recipe capture.** Four intakes: record, choose an audio file, paste a link (YouTube, Instagram, recipe sites), or paste text.
- Recording and audio files are transcribed **on device** (`RecipeAudioTranscriber`, `requiresOnDeviceRecognition = true`). Audio never leaves the phone. The recognizer follows the phone's language setting; Apple's on-device recognition covers Hindi but not Urdu or Punjabi, so desi words may come out spelled by ear.
- **Extraction runs server-side** in the `extract-recipe` Edge Function (Anthropic) with the user JWT. Quota: **5 extracts per user per 24h** for everyone, reserved atomically (`009_atomic_recipe_extraction_quota.sql`, #58). 402 `quota_exceeded` is "try tomorrow", not a paywall.
- Transcript saves publish a public card to the family recipe book; URL extracts stay private (THESIS).

**Supabase (verified 8 Oct 2026).**
- `extract-recipe` live is **version 9**, deployed 7 Oct 2026 at 4:10 PM ET. Its `index.ts` and `recipe_source.ts` are byte-identical to `main` at `2632437` (#61 merge), so #54, #58, #60, and #61 are live.
- `delete-account` live is version 3.
- Migrations 001 through 009 are applied, including both 009 files (`009_atomic_recipe_extraction_quota`, `009_recipe_book_card_ownership`) on 6 Oct 2026.
- Any later change under `supabase/functions/extract-recipe` is not live until `supabase functions deploy extract-recipe` runs. That needs Haaris's OK every time; agents do not deploy or run production SQL.

**Legal URLs** `samanpantry.com/privacy` and `/support` are live and in the binary (Settings, Auth, paywall).

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
- Account deletion goes through `delete-account` with the user JWT.
- Deletes go through `AppEnvironment.deleteRecord` so a tombstone is queued. Bare `context.delete` resurrects the row on the next pull.
- The app target is a synchronized Xcode group. Every `.swift` under `Saman/` compiles with no pbxproj entry, so an unreferenced file still ships. Delete dead code, do not park it.
- Deleted and staying deleted: Prices, `ReorderView` / `ReorderItemRow` / `RestockSheet`, `PantryListView` / `AddPantryView`. The live loop is item detail → list → mark bought. InventoryView is the pantry surface.
- Scanner is a data-entry method inside Add Item, not a destination.
- Password recovery: `resetPasswordForEmail` uses `redirectTo: samaan://auth-callback`. Do **not** treat `.passwordRecovery` as sign-out.
- RevenueCat entitlement id is `Saman Pro`, byte-for-byte with the dashboard. Do not "fix" it.
- Paywall bullets are source-controlled (`FreeLimits`). The remote RevenueCat paywall copy still has a retired grocery-delivery claim; do not load feature copy from it.
- `-UITesting` is a screenshot seed path, not a substitute for guest browse.

## Owner console: confirm, don't assume

These live outside the repo. Ask Haaris or check the console before stating either way:

- Old Anthropic key revoked in the Anthropic console.
- Pre-confirmed App Review demo account exists and still signs in.
- `samaan://auth-callback` is in Supabase Auth → URL Configuration → Redirect URLs.

## Do not

- Submit to App Review, release a version, or edit App Store Connect without Haaris's explicit OK.
- Deploy Edge Functions or run production SQL without Haaris's OK.
- Grow recipe CRUD into a meal planner or discovery cookbook.
- Add household sharing "because the models already have it."
- Ship "Alert me when below" without a real notification.
- Restore ReorderView or a mandatory-account splash.
- Push code branches casually: every push archives and uploads a TestFlight build.

## Next repo work (order)

1. Haaris finishes testing 1.3.1 on TestFlight (long recordings with pauses, long audio files, cancel mid-capture). Then, with his OK, submit 1.3.1 and the Desi Family Recipes custom product page version.
2. Attach a build to the 1.4 App Store draft only when there is a 1.4 binary.
3. Household mode only after the THESIS gates.
