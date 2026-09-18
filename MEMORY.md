# Project Memory
Last updated: 2026-09-18 | Branch: cursor/stale-launch-docs-334f
Memory health: 9/10

## Project Overview
Samaan — iOS pantry app for one desi kitchen. SwiftUI + SwiftData + Supabase `mcknboqvblbonmaebmjg` + RevenueCat. Product company: Saman Technologies LLC. Bundle `com.samanpantry.Saman`. THESIS.md wins product arguments.

## Where We Left Off
- **Current task:** Stale June launch reports and agent memory contradicted #20/#21. Docs PR only — no product rewrite.
- **Status:** Guest browse shipped in #20. Reorder UI deleted in #21. Xcode project is **1.0 (65)**. `1.0 (47)` was on TestFlight as of 30 Aug 2026. App Review rejected **64**; 65 is the next archive number in the repo — do not invent a TestFlight listing for 65. Not App Review ready. Owner-console work is still the blocker (SQL, deploy, revoke key, demo account, redirect URL).
- **Next immediate step:** Owner applies `003_recipes.sql` and `004_recipe_extraction_events.sql`, deploys `extract-recipe` and `delete-account`, revokes the old Anthropic key, creates a pre-confirmed App Review demo account, and adds `samaan://auth-callback` to Supabase Auth redirect URLs. Do not submit. Do not restore a login wall or ReorderView.
- **Open question:** none on the code side for recovery — `samaan://auth-callback` + `onOpenURL` + set-new-password UI are on main.

## Completed
- 2026-09-18 Deleted June `LAUNCH_REVIEW.md` / `APP_STORE_READINESS_REPORT.md`, duplicate `docs/launch/PrivacyInfo.xcprivacy`, and replaced the obsolete Edge Function spec with a pointer at `supabase/functions/`. Trued up skill, MEMORY, THESIS, and screenshot copy for guest browse + mark-bought restock.
- 2026-09-17 Deleted unreachable `ReorderView` / `ReorderItemRow` / private `RestockSheet`, trimmed the unwired LowStockBanner chevron, and dropped the two root `*.pages` thesis binaries (#21).
- 2026-09-15 Guest browse + in-binary Privacy/Terms/Support (Auth, Settings LEGAL, paywall inset). Unsigned launch reaches the tab shell. Auth only for sync, extract, delete account. Build 65 (#20).
- 2026-09-05 extract-recipe requires the user JWT and a 5/day quota table. Client sends the access token; 402 opens the paywall (or a tomorrow message if already Pro).
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
- [ ] Owner: apply `supabase/migrations/003_recipes.sql` in the Supabase SQL editor
- [ ] Owner: apply `supabase/migrations/004_recipe_extraction_events.sql`
- [ ] Owner: deploy the `extract-recipe` and `delete-account` Edge Functions
- [ ] Owner: revoke the old Anthropic key in the Anthropic console
- [ ] Owner: create a pre-confirmed demo account for App Review (email confirmation is on)
- [ ] Owner: add `samaan://auth-callback` to Supabase Auth → URL Configuration → Redirect URLs
- [x] Guest browse (#20) — do not restore a login wall
- [x] Reorder UI deleted (#21) — do not restore ReorderView
- [x] TestFlight 1.0 (47) as of 30 Aug 2026 (historical). Repo build is now 1.0 (65)
- [ ] Household mode stays off (THESIS)

## Blockers
- Recipes pull no-ops until `003_recipes.sql` is applied in prod.
- Recipe capture 500s until `004_recipe_extraction_events.sql` is applied and `extract-recipe` is redeployed.
- In-app account deletion fails until `delete-account` is deployed.
- Password-reset email will not bounce back into the app until the redirect URL is allow-listed.
- App Review still needs the pre-confirmed demo account for the extract/sync/delete paths that require a session. Guest browse is enough for pantry/list/recipe UI without an account.

## Key Decisions
| Date | Decision | Reasoning | Affects |
|------|----------|-----------|---------|
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
- [x] #2 restock writeback (now mark-bought; ReorderView later deleted)
- [x] Bidirectional sync + recipe sync + password reset + honest copy + iPhone-only
- [x] Live legal URLs
- [x] Guest browse (#20)
- [x] Reorder UI deleted (#21)
- [x] TestFlight 1.0 (47) — historical. Repo is 1.0 (65)
- [ ] Owner: recipes SQL, quota SQL, Edge Functions, Anthropic revoke, demo account, redirect URL
- [ ] App Review (do not submit until the owner items above are done)
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
- Old Anthropic key must still be revoked in the provider account.

## Key Files
| File | Purpose |
|------|---------|
| THESIS.md | Product forcing function |
| Saman/App/RootView.swift | Tab shell (Home, Pantry, Lists, Recipes). Guest browse: no session still reaches tabs. AuthView for sync / extract / delete / password recovery |
| Saman/App/AppEnvironment.swift | auth, modelContainer, syncNow(), deleteRecord(), requireAccount() |
