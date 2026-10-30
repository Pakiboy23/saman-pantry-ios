# Project Memory
Last updated: 2026-10-30 | Branch: cursor/documentation-automation-system-2a57
Memory health: 8/10

## Project Overview
Samaan Pantry: iOS pantry app for one desi kitchen. SwiftUI + SwiftData + Supabase `mcknboqvblbonmaebmjg` + RevenueCat. Legal entity: Saman Technologies LLC dba Samaan Technologies. Bundle `com.samanpantry.Saman` and `samanpantry.com` stay single-a. Paid tier: Samaan Pro. THESIS.md wins product arguments.

## Where We Left Off
- **App Store:** Last verified live is **Samaan Pantry 1.3 (build 133)**, released 2026-10-05 (`788fafd`: recording, audio-file intake, public family recipe book). Do not claim 1.5 or 1.6 is live without App Store Connect.
- **main:** marketing **1.6**. Train: billing + onboarding (#66), 1.5 bump (#67), community-book URL opt-in (#68), HeyCatch (#69/#71), Samaan copy (#70), RevenueCat `logIn` (#76), private family cookbooks (#74). Xcode Cloud supplies build numbers; `CURRENT_PROJECT_VERSION` (108) in the pbxproj is not the App Store Connect build number.
- **Server:** last verified live `extract-recipe` is **version 9** (2026-10-07, `2632437`). #63 and #66 are on `main` and need `supabase functions deploy extract-recipe` after migration 011. Migrations 001–009 were applied (009s on 2026-10-06). **011, 012, and the 20261024 family-books pair are repo-only until Haaris applies them.** Webhook/sync functions are repo-only until deployed.
- **Next immediate step:** Owner applies 011 + 012 and deploys `extract-recipe` (set `REVENUECAT_SECRET_API_KEY` if Pro should skip quota), then family-books go-steps. Nothing goes to App Review without Haaris's explicit OK.
- **Open question:** owner-console items below are unconfirmed; ask, don't assume.

## Completed
- 2026-10-30 Docs: skill and MEMORY match 1.6 including #71/#74/#76. Runbooks: `docs/billing-and-extract-quota.md`, `docs/analytics.md`, `docs/family-cookbooks.md`.
- 2026-10-24 Family cookbooks for 1.6 (#74): private families, invites, snapshots, RevenueCat webhook/sync in-repo. Go-steps in `docs/family-books-go-steps.md`.
- 2026-10-26 Identify RevenueCat with the Supabase user id (#76).
- 2026-10-21 HeyCatch bind only for signed-in users (#71). HeyCatch product analytics (#69). Marketing 1.6.
- 2026-10-15 Samaan copy / gender-neutral demo strings (#70).
- 2026-10-12 Family book opt-in for link recipes (#68, migration 012). Billing free-tier + Pro paywall + first-launch onboarding (#66, migration 011). Marketing 1.5 (#67).
- 2026-10-08 Docs: skill and MEMORY match 1.3 live / 1.3.1 on main (since superseded). extract-recipe v9. Parser hardening (#61), #63 meta/caption scan on main (not deployed).
- 2026-10-07 Voice capture keeps the full transcript; link-shaped miss errors fixed (#60). Stale auth sessions no longer restore signed-out accounts (#59).
- 2026-10-06 Atomic 5/day extraction quota (#58). Cross-owner recipe book card mutations blocked (#57). JSON-LD instruction budget (#54). Int-conversion crash fix (#56). Both 009 migrations applied.
- 2026-10-05 1.3 (133) released. Recording keeps the full transcript across pauses (#49); marketing 1.3.1 (#50).
- 2026-10-04 On-device transcription of a recording or audio file into the recipe extract (#46). Public family recipe book for transcript saves (#44).
- 2026-09-26 Recipe link extraction (#39), shipped in 1.2 (119) alongside Samaan Pro. Migrations 003 through 006 applied. 1.2 prices were Monthly $4.99 / Yearly $39.99 / Lifetime $79.99 — **not** the current fixture.
- 2026-09-25 Anonymous usage events and one-time Anthropic consent (#36), shipped in 1.1 (106).
- 2026-09-18 Deleted June `LAUNCH_REVIEW.md` / `APP_STORE_READINESS_REPORT.md`, duplicate `docs/launch/PrivacyInfo.xcprivacy`, and replaced the obsolete Edge Function spec with a pointer at `supabase/functions/`. Trued up skill, MEMORY, THESIS, and screenshot copy for guest browse + mark-bought restock.
- 2026-09-17 Deleted unreachable `ReorderView` / `ReorderItemRow` / private `RestockSheet`, trimmed the unwired LowStockBanner chevron, and dropped the two root `*.pages` thesis binaries (#21).
- 2026-09-15 Guest browse + in-binary Privacy/Terms/Support (Auth, Settings LEGAL, paywall inset). Unsigned launch reaches the tab shell. Auth only for sync, extract, delete account. Build 65 (#20).
- 2026-09-19 Monetization honesty (1.2-era): named the then-real gates (30 pantry items, extra list). **Superseded 2026-10-12** — pantry/lists are unlimited; 402 is a Pro upsell; Pro lifts extract when RevenueCat verifies.
- 2026-09-05 extract-recipe requires the user JWT and a quota table. Client sends the access token.
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
- [ ] Owner: apply `011_billing_grandfathered_and_quota.sql` and `012_recipe_book_url_opt_in.sql` in prod
- [ ] Owner: set `REVENUECAT_SECRET_API_KEY` and deploy `extract-recipe` after 011
- [ ] Owner: family-books go-steps (SQL pair, `REVENUECAT_SECRET_KEY`, webhook auth, AASA)
- [ ] Update hosted `samanpantry.com/privacy` for HeyCatch and family cookbooks before the 1.6 submit
- [ ] With Haaris's OK: attach a 1.6 TestFlight build and submit
- [ ] Draft #78: ignore sandbox RevenueCat webhooks; revoke TRANSFER donors
- [ ] Draft #79: keep family recipe copies out of the public community book
- [ ] Owner, confirm don't assume: old Anthropic key revoked
- [ ] Owner, confirm don't assume: pre-confirmed App Review demo account still works
- [ ] Owner, confirm don't assume: `samaan://auth-callback` in Supabase Auth redirect URLs
- [x] Guest browse (#20). Do not restore a login wall
- [x] Reorder UI deleted (#21). Do not restore ReorderView
- [x] HeyCatch bind only for signed-in users (#71)
- [ ] Household mode stays off (THESIS)

## Blockers
- None in the repo. Release steps (migrate, deploy, submit, console checks) are Haaris's call.

## Key Decisions
| Date | Decision | Reasoning | Affects |
|------|----------|-----------|---------|
| 2026-10-24 | Private family cookbooks; Pro/grandfathered to create; join free | Recipe sharing among invited members is not household mode | FamilyService, family_* tables, paywall `.createFamily` |
| 2026-10-26 | Identify RevenueCat with the lowercased Supabase user UUID | Webhook/sync/extract-recipe all key off that id; keep guest anonymous purchases | PurchaseSessionBinding, revenuecat-sync |
| 2026-10-21 | HeyCatch + anonymous Supabase events; bind after session | Product analytics without recipe text or personal properties; no guest identify | HeyCatch, AnalyticsService, privacy docs |
| 2026-10-12 | URL recipes opt into the community book | Transcripts stay auto-public; link extracts stay private until the owner adds them | Recipe.shareInFamilyBook, 012, recipe-book harness |
| 2026-10-12 | Split free extract quota; Pro is unlimited extracts; pantry/lists unlimited | New accounts get 5 lifetime; pre-2026-10-12 keep 5/day. 402 opens paywall. 503 is retry. | FreeLimits, extract-recipe, 011, OnboardingView |
| 2026-10-04 | Transcribe on device; extract on the server | Audio stays on the phone; extraction needs the model and the quota | RecipeAudioTranscriber, extract-recipe |
| 2026-09-18 | Delete June launch reports; truth-up skill/MEMORY/THESIS | Stale launch copy would send the next agent to undo #20/#21 | launch docs, skill |
| 2026-09-17 | Delete ReorderView + Pages thesis binaries | Unreachable tab; live loop is item detail → list → mark bought. `.pages` copies were ~777KB each next to THESIS.md | ReorderView, LowStockBanner |
| 2026-09-15 | Guest browse; legal links without login | App Review 5.1.1(v) + 3.1.2(c). Auth only for sync / extract / delete | RootView, AuthView, Settings, paywall |
| 2026-09-05 | Delete PantryListView / AddPantryView | Unreachable; synchronized group would ship them | Inventory |
| 2026-09-05 | extract-recipe JWT + quota table | Anon Bearer was an open Anthropic proxy | extract-recipe, RecipeExtractionService |
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
- [x] Billing split + onboarding + community-book URL opt-in + HeyCatch + family cookbooks on `main` (1.6)
- [ ] Prod 011/012 + extract-recipe deploy; family-books go-steps; then 1.6 App Review after Haaris's OK
- [ ] Household mode only after 500 WAU + 30% asking + sync stable

## Strategic decisions (do not reopen)
- Primary user: 25-35 diaspora adult, solo kitchen, single device
- Household/sharing: v2 only, conditions in THESIS.md. Private family cookbooks are not household mode.
- Core loop: low → list → shop → bought → pantry updates
- Cuts approved: Prices tab (view deleted 2026-08-29), Scanner as top-level tab, Settings as tab, PantryListView / AddPantryView (deleted 2026-09-05), ReorderView / ReorderItemRow (deleted 2026-09-17)
- Scanner stays inside Add Item. It is a data-entry method, not a destination
- Cultural specificity is the moat — no generic mode
- Pantry-first: recipes support the shopping list. The public community book and private family cookbooks are intentional.
- Guest browse stays. Do not restore a login wall.

## Known issues (open)
- `image_url` is modeled, migrated, and synced but nothing populates it. No photo picker, no Storage upload.
- Xcode Cloud's single `Default` workflow archives and uploads a TestFlight build on every branch push. Use `[ci skip]` for docs-only pushes.
- Hosted privacy page may still omit HeyCatch and family cookbook fields. Repo copy is in `docs/launch/legal-and-privacy.md`.
- `FamilyRecipeDetailView.saveCopy()` can publish a transcript-shaped copy to Community. Draft #79.
- RevenueCat webhook on `main` does not ignore sandbox events. Draft #78.

## Key Files
| File | Purpose |
|------|---------|
| THESIS.md | Product forcing function |
| docs/billing-and-extract-quota.md | Pro, grandfathered vs lifetime extract, RC identity, 402/503, deploy order |
| docs/analytics.md | Supabase `events` + HeyCatch bind/outbox |
| docs/family-cookbooks.md | Private families: invites, snapshots, Pro gate |
| docs/family-books-go-steps.md | Owner apply/deploy for family SQL + webhook + AASA |
| Saman/App/RootView.swift | Onboarding gate, then tab shell. Guest browse after onboarding. AuthView for sync / extract / delete / password recovery |
| Saman/App/AppEnvironment.swift | auth, modelContainer, syncNow(), deleteRecord(), requireAccount(), extractionQuota |
| Saman/Core/Services/FreeLimits.swift | Free/Pro copy, fixture prices, extract counter labels, family Pro policy |
| Saman/Core/Services/FamilyService.swift | Private family RPCs and invite URLs |
| Saman/Core/Services/PurchaseService.swift | `Saman Pro`, logIn/logOut, revenuecat-sync |
| Saman/Features/Onboarding/OnboardingView.swift | First-launch only (`samaan.hasCompletedOnboarding`) |
| Saman/Core/Services/HeyCatch.swift | Product analytics SDK wrapper |
| supabase/migrations/011_billing_grandfathered_and_quota.sql | `user_accounts`, reserve RPC, `my_extraction_quota_status` |
| supabase/migrations/012_recipe_book_url_opt_in.sql | `share_in_family_book` for link recipes |
| supabase/migrations/20261024000000_family_books.sql | Private families |
