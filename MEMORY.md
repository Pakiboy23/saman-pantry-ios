# Project Memory
Last updated: 2026-10-08 | Branch: grok/docs-current-state
Memory health: 9/10

## Project Overview
Samaan Pantry: iOS pantry app for one desi kitchen. SwiftUI + SwiftData + Supabase `mcknboqvblbonmaebmjg` + RevenueCat. Legal entity: Saman Technologies LLC dba Samaan Technologies. Bundle `com.samanpantry.Saman` and `samanpantry.com` stay single-a. Paid tier: Samaan Pro. THESIS.md wins product arguments.

## Where We Left Off
- **App Store:** Samaan Pantry **1.3 (build 133)** is live, released 2026-10-05. Build 133 is `main` at `788fafd` (recording, audio-file intake, family recipe book). A 1.4 App Store version is a metadata-only draft in App Store Connect (no build).
- **main:** marketing **1.3.1**. TestFlight 1.3.1 builds run through 161 (2026-10-07). 158 is `main` at the #61 merge; 157 (the #61 branch head) is the last build Haaris was asked to test. Xcode Cloud supplies build numbers; `CURRENT_PROJECT_VERSION` (107) in the pbxproj is not the App Store Connect build number.
- **Server:** `extract-recipe` live is **version 9** (deployed 2026-10-07 4:10 PM ET), byte-identical to `main` at `2632437`, so #54, #58, #60, #61 are live. Migrations 001 through both 009 files are applied (009s on 2026-10-06). Later function changes (for example #63) need `supabase functions deploy extract-recipe` with Haaris's OK.
- **Next immediate step:** Haaris tests 1.3.1 on TestFlight. With his OK, submit 1.3.1 and the Desi Family Recipes product page version. Nothing goes to App Review without his explicit OK.
- **Open question:** owner-console items below are unconfirmed; ask, don't assume.

## Completed
- 2026-10-08 Docs: skill and MEMORY match 1.3 live / 1.3.1 on main, Xcode Cloud build numbers, extract-recipe v9, and Samaan Pro prices. Removed the build 65 / "do not submit" guidance.
- 2026-10-07 Parser hardening and capture cancellation (#61); `extract-recipe` v9 deployed from that main.
- 2026-10-07 Voice capture keeps the full transcript; link-shaped miss errors fixed (#60). Stale auth sessions no longer restore signed-out accounts (#59).
- 2026-10-06 Atomic 5/day extraction quota (#58). Cross-owner recipe book card mutations blocked (#57). JSON-LD instruction budget (#54). Int-conversion crash fix (#56). Both 009 migrations applied.
- 2026-10-05 1.3 (133) released. Recording keeps the full transcript across pauses (#49); marketing 1.3.1 (#50).
- 2026-10-04 On-device transcription of a recording or audio file into the recipe extract (#46). Public family recipe book for transcript saves (#44).
- 2026-09-26 Recipe link extraction (#39), shipped in 1.2 (119) alongside Samaan Pro (Monthly $4.99, Yearly $39.99, Lifetime $79.99). Migrations 003 through 006 applied.
- 2026-09-25 Anonymous usage events and one-time Anthropic consent (#36), shipped in 1.1 (106).
- 2026-09-18 Deleted June `LAUNCH_REVIEW.md` / `APP_STORE_READINESS_REPORT.md`, duplicate `docs/launch/PrivacyInfo.xcprivacy`, and replaced the obsolete Edge Function spec with a pointer at `supabase/functions/`. Trued up skill, MEMORY, THESIS, and screenshot copy for guest browse + mark-bought restock.
- 2026-09-17 Deleted unreachable `ReorderView` / `ReorderItemRow` / private `RestockSheet`, trimmed the unwired LowStockBanner chevron, and dropped the two root `*.pages` thesis binaries (#21).
- 2026-09-15 Guest browse + in-binary Privacy/Terms/Support (Auth, Settings LEGAL, paywall inset). Unsigned launch reaches the tab shell. Auth only for sync, extract, delete account. Build 65 (#20).
- 2026-09-19 Monetization honesty: Settings / StoreKit / paywall name the real gates (30 pantry items, extra list from Lists tab). Extract 402 is try-tomorrow for everyone — Pro does not lift the 5/day cap. Restore Purchases is on the free Settings surface. Shared `FreeLimits`.
- 2026-09-05 extract-recipe requires the user JWT and a 5/day quota table. Client sends the access token; 402 is try-tomorrow for everyone (function does not check Pro).
- 2026-09-05 Password recovery completes in-app: URL scheme, `onOpenURL`, `redirectTo`, `.passwordRecovery` is not a sign-out.
- 2026-09-05 Deleted unreachable `PantryListView` / `AddPantryView`.
- 2026-08-29 `samanpantry.com/privacy` and `/support` verified live: both return 200. Apex 307s to `www`, which is fine for App Review and for `Config.privacyPolicyURL` / `Config.supportURL`. Legal URLs are no longer a blocker.
- 2026-08-29 Deleted dead scaffolding: `ItemRepository` (never injected, and its bare `context.delete` was a copy-paste trap) and `PricesView` (orphaned stub, already cut from the tab bar).
- 2026-08-23 Pull-sync + tombstones. Upload dirty, then pull. Local dirty wins. Missing server row deletes clean local.
- 2026-08-23 Recipe `updatedAt` + `recipes` table migration. Recipe deletes now tombstone.
- 2026-08-23 Password reset on AuthView. Friendly auth errors.
- 2026-08-23 Item detail copy is "Flag as low below" — no notification lie.
- 2026-08-23 PrivacyInfo in the synchronized Saman/ group. Device family iPhone only.
- 2026-08-23 samaan-pantry-expert skill on main via #5.
- 2026-04-20 #2 Reorder writeback (tab later deleted; restock is mark-bought).
- 2026-04-19 THESIS.md + foundation.

## Active Work
- [ ] Haaris: test 1.3.1 on TestFlight (long recording with pauses, long audio file, cancel mid-capture)
- [ ] With Haaris's OK: submit 1.3.1; submit the Desi Family Recipes product page version
- [ ] With Haaris's OK: deploy `extract-recipe` after any further function change (#63 is open)
- [ ] Owner, confirm don't assume: old Anthropic key revoked
- [ ] Owner, confirm don't assume: pre-confirmed App Review demo account still works
- [ ] Owner, confirm don't assume: `samaan://auth-callback` in Supabase Auth redirect URLs
- [x] Guest browse (#20). Do not restore a login wall
- [x] Reorder UI deleted (#21). Do not restore ReorderView
- [ ] Household mode stays off (THESIS)

## Blockers
- None in the repo. Release steps (submit, deploy, console checks) are Haaris's call.

## Key Decisions
| Date | Decision | Reasoning | Affects |
|------|----------|-----------|---------|
| 2026-10-04 | Transcribe on device; extract on the server | Audio stays on the phone; extraction needs the model and the quota | RecipeAudioTranscriber, extract-recipe |
| 2026-09-19 | Monetization copy matches real gates; 402 is not a Pro upsell | Settings said "support development"; StoreKit said "premium pantry and recipe features"; extract 402 opened paywall though Pro does not lift the 5/day cap | FreeLimits, Settings, StoreKit, RecipeCaptureView |
| 2026-09-18 | Delete June launch reports; truth-up skill/MEMORY/THESIS | Stale launch copy would send the next agent to undo #20/#21 | launch docs, skill |
| 2026-09-17 | Delete ReorderView + Pages thesis binaries | Unreachable tab; live loop is item detail → list → mark bought. `.pages` copies were ~777KB each next to THESIS.md | ReorderView, LowStockBanner |
| 2026-09-15 | Guest browse; legal links without login | App Review 5.1.1(v) + 3.1.2(c). Auth only for sync / extract / delete | RootView, AuthView, Settings, paywall |
| 2026-09-05 | Delete PantryListView / AddPantryView | Unreachable; synchronized group would ship them | Inventory |
| 2026-09-05 | extract-recipe JWT + 5/day quota | Anon Bearer was an open Anthropic proxy | extract-recipe, RecipeExtractionService |
| 2026-08-29 | Delete unreferenced files rather than quarantine them | The Xcode target uses `PBXFileSystemSynchronizedRootGroup`, so every file on disk compiles and ships. An orphan is not free | ItemRepository, PricesView |
| 2026-08-23 | Tombstones in UserDefaults, flushed before upload/pull | Deletes must survive a killed process | SyncManager, AppEnvironment.deleteRecord |
| 2026-08-23 | Local dirty wins over newer server | Avoid clobbering an in-flight edit | SyncReconcile |
| 2026-08-23 | iPhone only | UI is iPhone-designed; no iPad screenshots | pbxproj TARGETED_DEVICE_FAMILY |
| 2026-08-23 | No push alerts in v1 | Copy was lying; flagging as low is enough | ItemDetailView |
| 2026-04-20 | Restock UX: mark bought on the list restocks pantry | Explicit commit, no lying to user. ReorderView later deleted | ShoppingListDetailView |
| 2026-04-19 | SwiftData local + Supabase auth/sync | Native Apple, RLS for access | All models |
| 2026-04-19 | isDirty flag pattern for sync | Simple optimistic tracking | Models, SyncManager |

## Roadmap (do in order)
- [x] Restock writeback, bidirectional sync, recipe sync, password reset, iPhone-only
- [x] Live legal URLs, guest browse (#20), Reorder UI deleted (#21)
- [x] 1.0 through 1.3 on the App Store; Samaan Pro since 1.2
- [ ] 1.3.1 (recording fix) after Haaris's TestFlight test and OK
- [ ] Household mode only after 500 WAU + 30% asking + sync stable

## Strategic decisions (do not reopen)
- Primary user: 25-35 diaspora adult, solo kitchen, single device
- Household/sharing: v2 only, conditions in THESIS.md
- Core loop: low → list → shop → bought → pantry updates
- Cuts approved: Prices tab (view deleted 2026-08-29), Scanner as top-level tab, Settings as tab, PantryListView / AddPantryView (deleted 2026-09-05), ReorderView / ReorderItemRow (deleted 2026-09-17)
- Scanner stays inside Add Item. It is a data-entry method, not a destination
- Cultural specificity is the moat — no generic mode
- Not a recipe app. Recipes exist to feed the shopping list.
- Guest browse stays. Do not restore a login wall.

## Known issues (open)
- `image_url` is modeled, migrated, and synced but nothing populates it. No photo picker, no Storage upload.
- Xcode Cloud's single `Default` workflow archives and uploads a TestFlight build on every branch push. Use `[ci skip]` for docs-only pushes.

## Key Files
| File | Purpose |
|------|---------|
| THESIS.md | Product forcing function |
| Saman/App/RootView.swift | Tab shell (Home, Pantry, Lists, Recipes). Guest browse: no session still reaches tabs. AuthView for sync / extract / delete / password recovery |
| Saman/App/AppEnvironment.swift | auth, modelContainer, syncNow(), deleteRecord(), requireAccount() |
