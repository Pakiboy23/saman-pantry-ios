# Project Memory
Last updated: 2026-11-24 | Branch: main
Memory health: 9/10

## Project Overview
Samaan Pantry: iOS pantry app for one desi kitchen. SwiftUI + SwiftData + Supabase `mcknboqvblbonmaebmjg` + RevenueCat. Legal entity: Saman Technologies LLC dba Samaan Technologies. Bundle `com.samanpantry.Saman` and `samanpantry.com` stay single-a. Paid tier: Samaan Pro. THESIS.md wins product arguments.

## Where We Left Off
- **App Store:** **Samaan Pantry 1.7 is live**, released 2026-11-23 (build number not recorded here). Prior releases: 1.3 (133, 2026-10-05), 1.2 (119), 1.1 (106), 1.0 (89). **1.8 (218) was submitted to App Review on 2026-11-23** (Community opt-in, #98) and is not approved yet. Do not claim a later version is live without App Store Connect.
- **main:** marketing **1.8** (#98). 1.8 adds Community opt-in per recipe (#98) and the docs true-up (#99). 1.7 content: server transcription PRs A–D (#83/#84/#86/#92/#93), dark/tinted icons (#90), gallery review doc (#91), `revenuecat-sync` on v1 subscribers (#94). Xcode Cloud supplies build numbers; `CURRENT_PROJECT_VERSION` (108 in the pbxproj) is not the App Store Connect build number.
- **Server (verified 2026-11-16 via the Supabase connector; #94 not confirmed deployed):** `extract-recipe` **version 21** is live and byte-identical to `main` at #85 (billing, URL extraction, audio route, speech prompt rules 4-6, alternatives stay one ingredient). v20 = #84 and v19 = #83 are rollbacks. Migrations through `011`, `012`, both family-books migrations, and `20261123000000_community_opt_in` (applied 2026-11-23, verified via the connector) are applied. Also live: `delete-account` v11, `revenuecat-sync` v8 (pre-#94 v2 path), `revenuecat-webhook` v9, and `asr-bakeoff` v4 (not in the repo; leftover from the engine bake-off). **Live `revenuecat-webhook` is a hand-deployed variant, not the repo file:** it ignores sandbox events but ignores `TRANSFER` (no donor revoke), unlike #78 on `main`. **Live `revenuecat-sync` v8 is not #94.** Repo code uses `REVENUECAT_SECRET_API_KEY` and `/v1/subscribers`. Secret names are not visible to the connector; confirm in the dashboard.
- **Server transcription (spec `docs/server-transcription-spec.md`):** PRs A–D are on `main`. PR A (#83) live in v19+. PR B (#84) + alternatives (#85) live in v21. PR C (#86) records AAC to a file and uploads it; Apple recognizer gone. PR D (#92/#93) is consent v2, PrivacyInfo audio, and store-listing drafts. Live 1.7 uploads the recording for server transcription. Never say audio stays on the phone for a 1.7 build.
- **Next immediate step:** 1.8 (218) is in App Review. When it clears, release it before the Product Hunt launch (Haaris's call). In parallel, owner deploys repo `revenuecat-sync` (#94) if live is still v8, decides webhook #78 vs live v9, and confirms the hosted privacy page covers HeyCatch, family cookbooks, and server transcription. Nothing is submitted or released without Haaris's explicit OK.
- **Open question:** owner-console items below are unconfirmed; ask, don't assume. Two launch PRs are open as drafts: #97 (Product Hunt copy) and #100 (App Store creative + PH launch video).

## Completed
- 2026-11-24 PR #100 opened (draft): App Store creative, 3 screenshots, Product Hunt launch video, render scripts under `marketing/`.
- 2026-11-23 **1.7 released on the App Store.** **1.8 (218) submitted to App Review** the same day. Community is opt-in for every recipe (#98, migration `20261123000000_community_opt_in`, applied in prod). Marketing 1.8. Docs true-up (#99). PH copy draft (#97, open).
- 2026-11-20 Docs: skill/MEMORY/runbooks match 1.7, PRs C/D shipped, `revenuecat-sync` v1 key (#94). Live sync still unverified as v8.
- 2026-11-18 `revenuecat-sync` uses v1 `REVENUECAT_SECRET_API_KEY` and `/subscribers` (#94). Privacy manifest matches the live App Privacy label (#93); PR D disclosures (#92).
- 2026-11-16 Server transcription PR C (#86): record to file, upload, Apple recognizer gone. PR A (#83) deployed as `extract-recipe` v19 with Haaris's OK; spec merged (#82). Sandbox webhook filter + TRANSFER donor revoke on `main` (#78) — the live webhook differs, see Server above.
- 2026-11-06 Docs: skill and MEMORY match 1.6 including #71/#74/#76/#79. Runbooks: `docs/billing-and-extract-quota.md`, `docs/analytics.md`, `docs/family-cookbooks.md`. Prior docs PRs #72 and #80 never merged.
- 2026-11-01 Family `saveCopy` stays a private `.url` recipe and does not auto-publish to Community (#79).
- 2026-10-26 Identify RevenueCat with the Supabase user id (#76).
- 2026-10-24 Family cookbooks for 1.6 (#74): private families, invites, snapshots, RevenueCat webhook/sync in-repo. Go-steps in `docs/family-books-go-steps.md`.
- 2026-10-21 HeyCatch bind only for signed-in users (#71). HeyCatch product analytics (#69). Marketing 1.6. Samaan copy / gender-neutral demo strings (#70, 10-15).
- 2026-10-12 Family book opt-in for link recipes (#68, migration 012). Billing free-tier + Pro paywall + first-launch onboarding (#66, migration 011). Marketing 1.5 (#67).
- 2026-10-08 Docs: skill and MEMORY match 1.3 live / 1.3.1 on main (since superseded). extract-recipe v9. Parser hardening (#61), #63 meta/caption scan on main (not deployed).
- 2026-10-07 Voice capture keeps the full transcript; link-shaped miss errors fixed (#60). Stale auth sessions no longer restore signed-out accounts (#59).
- 2026-10-06 Atomic 5/day extraction quota (#58). Cross-owner recipe book card mutations blocked (#57). JSON-LD instruction budget (#54). Int-conversion crash fix (#56). Both 009 migrations applied.
- 2026-10-05 1.3 (133) released. Recording keeps the full transcript across pauses (#49); marketing 1.3.1 (#50).
- 2026-10-04 On-device transcription of a recording or audio file into the recipe extract (#46). Public family recipe book for transcript saves (#44).
- 2026-09-26 Recipe link extraction (#39), shipped in 1.2 (119) alongside Samaan Pro. Migrations 003-006 applied. 1.2 prices were Monthly $4.99 / Yearly $39.99 / Lifetime $79.99 — **not** the current fixture.
- 2026-09-25 Anonymous usage events and one-time Anthropic consent (#36), shipped in 1.1 (106).
- 2026-09-15..19 Guest browse + in-binary legal links, build 65 (#20). ReorderView / RestockSheet / `*.pages` deleted (#21). June launch reports deleted, docs trued up. 1.2-era monetization copy superseded 2026-10-12 (pantry and lists are unlimited).
- 2026-08-23..09-05 Foundation: pull-sync + tombstones (local dirty wins), recipe `updatedAt` + tombstones, extract-recipe JWT + quota, in-app password recovery, iPhone-only, PrivacyInfo in the synchronized group, "Flag as low below" copy, `PantryListView` / `AddPantryView` / `ItemRepository` / `PricesView` deleted, live legal URLs, expert skill on main (#5).
- 2026-04 THESIS.md + foundation (#2 restock writeback; the Reorder tab was deleted later, restock is mark-bought).

## Active Work
- [x] 011, 012, family-books migrations applied in prod (verified 2026-11-16)
- [x] `20261123000000_community_opt_in` applied in prod (verified 2026-11-23)
- [x] Community opt-in toggle per recipe on `main`, ships in 1.8 (#98)
- [x] `extract-recipe` deployed (v19, 2026-11-16)
- [ ] Owner, confirm don't assume: `REVENUECAT_SECRET_API_KEY` set (else Pro is metered as free)
- [ ] Deploy repo `revenuecat-sync` (#94) if live is still v8
- [ ] Decide: deploy repo `revenuecat-webhook` (#78, TRANSFER donor revoke) over the hand-deployed v9
- [ ] Delete `asr-bakeoff` from prod if the bake-off is done
- [ ] Owner: family-books remaining go-steps (AASA, webhook auth, App Privacy for 1.7)
- [ ] Confirm hosted `samanpantry.com/privacy` covers HeyCatch, family cookbooks, and server transcription (1.7 is live; not verified here)
- [x] 1.8 (218) submitted to App Review (2026-11-23)
- [ ] Release 1.8 once App Review approves, before the Product Hunt launch (Haaris's call)
- [ ] Land the launch assets: #97 (PH copy) and #100 (creative + video) are open drafts
- [x] #78 on `main`: ignore sandbox RevenueCat webhooks; revoke TRANSFER donors (not the live variant)
- [x] Server transcription PR A (#83) merged and live
- [x] Server transcription PR B (#84) merged, live in v20
- [x] Prompt follow-up: alternatives ("X or Y") stay one ingredient (#85, live in v21)
- [x] Server transcription PR C (iOS record-to-file + upload) (#86)
- [x] Server transcription PR D (copy/privacy, PrivacyInfo audio) (#92/#93). Owner decisions in spec section 9 still open.
- [x] #79: family `saveCopy` stays out of the public community book
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
| 2026-11-23 | Community sharing is opt-in per recipe | Transcript saves were auto-publishing a public card. The owner now sets "Share to Community"; the 6 cards that already existed were kept by backfilling the flag | Recipe.shareInFamilyBook, 20261123000000_community_opt_in, Recipes UI |
| 2026-11-16 | Prompt changes gate on `scripts/recipe-eval.ts` against a private recording set | The repo is public; recordings and transcripts never enter it. The script tests the checkout's prompt before deploy | prompts.ts, release checklist |
| 2026-11-16 | Move recording transcription to the server (ElevenLabs Scribe v2), engine as a server setting | Apple on-device mangles desi words and duplicates partials; Scribe v2 got bhindi/zeera right on a real recording | extract-recipe, RecipeAudioTranscriber (removed in PR C), privacy copy (PR D) |
| 2026-10-24 | Private family cookbooks; Pro/grandfathered to create; join free | Recipe sharing among invited members is not household mode | FamilyService, family_* tables, paywall `.createFamily` |
| 2026-10-26 | Identify RevenueCat with the lowercased Supabase user UUID | Webhook/sync/extract-recipe all key off that id; keep guest anonymous purchases | PurchaseSessionBinding, revenuecat-sync |
| 2026-10-21 | HeyCatch + anonymous Supabase events; bind after session | Product analytics without recipe text or personal properties; no guest identify | HeyCatch, AnalyticsService, privacy docs |
| 2026-10-12 | URL recipes opt into the community book | Transcripts stay auto-public; link extracts stay private until the owner adds them | Recipe.shareInFamilyBook, 012, recipe-book harness |
| 2026-10-12 | Split free extract quota; Pro is unlimited extracts; pantry/lists unlimited | New accounts get 5 lifetime; pre-2026-10-12 keep 5/day. 402 opens paywall. 503 is retry. | FreeLimits, extract-recipe, 011, OnboardingView |
| 2026-11-18 | `revenuecat-sync` uses v1 `REVENUECAT_SECRET_API_KEY` | The v2 secret was never set; extract-recipe already had the v1 key | revenuecat-sync |
| 2026-10-04 | Transcribe on device; extract on the server (superseded 2026-11-16, PR C #86) | Audio stays on the phone; extraction needs the model and the quota | RecipeAudioTranscriber (removed), extract-recipe |
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
- [x] 1.7 live on the App Store (2026-11-23)
- [ ] Release 1.8 (in App Review: Community opt-in) before the Product Hunt launch, after Haaris's OK
- [ ] Remaining family-books go-steps + hosted privacy confirmation
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
- Live `revenuecat-webhook` v9 is not the repo file and does not revoke TRANSFER donors.
- Live `revenuecat-sync` v8 (checked 2026-11-16) is not #94. Repo uses `REVENUECAT_SECRET_API_KEY`.
- `asr-bakeoff` is live in prod and not in the repo.
- Live 1.7 cannot share a spoken recipe to Community and still labels them "in the family book". The opt-in toggle ships in 1.8.

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
| supabase/functions/extract-recipe/prompts.ts | Extraction prompts; speech rules 4-6 |
| scripts/recipe-eval.ts | Private recording test set runner; schema in `scripts/recipe-eval.schema.json` |
| supabase/migrations/011_billing_grandfathered_and_quota.sql | `user_accounts`, reserve RPC, `my_extraction_quota_status` |
| supabase/migrations/012_recipe_book_url_opt_in.sql | `share_in_family_book` for link recipes |
| supabase/migrations/20261024000000_family_books.sql | Private families |
| supabase/migrations/20261123000000_community_opt_in.sql | Per-recipe Community opt-in, `family_label_for()` |
| marketing/ | App Store creative, screenshots, PH launch video + render scripts (#100, draft) |
