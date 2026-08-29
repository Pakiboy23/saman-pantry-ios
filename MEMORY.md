# Project Memory
Last updated: 2026-08-29 | Session 4 | Branch: claude/samaan-pantry-cleanup-24cwo6
Memory health: 9/10

## Project Overview
Samaan — iOS pantry app for one desi kitchen. SwiftUI + SwiftData + Supabase `mcknboqvblbonmaebmjg` + RevenueCat. Product company: Saman Technologies LLC. Bundle `com.samanpantry.Saman`. THESIS.md wins product arguments.

## Where We Left Off
- **Current task:** Live-fact cleanup. Legal URLs confirmed live, dead scaffolding deleted.
- **Status:** Not on TestFlight. Everything still standing between the repo and TestFlight is owner-side, in the Supabase and Anthropic dashboards. Nothing in the app code is blocking.
- **Next immediate step:** Owner applies `supabase/migrations/003_recipes.sql`, deploys `extract-recipe` and `delete-account`, revokes the old Anthropic key, and creates a pre-confirmed App Review demo account. Then TestFlight.
- **Open question:** Deep-link password recovery is still not in-app. `resetPasswordForEmail` sends the mail; tapping the link lands wherever the Supabase Site URL points. The app registers no URL scheme and has no `onOpenURL`, so recovery cannot complete inside the app.

## Completed
- 2026-08-29 `samanpantry.com/privacy` and `/support` verified live: both return 200. Apex 307s to `www`, which is fine for App Review and for `Config.privacyPolicyURL` / `Config.supportURL`. Legal URLs are no longer a blocker.
- 2026-08-29 Deleted dead scaffolding: `ItemRepository` (never injected, and its bare `context.delete` was a copy-paste trap) and `PricesView` (orphaned stub, already cut from the tab bar).
- 2026-08-23 Pull-sync + tombstones. Upload dirty, then pull. Local dirty wins. Missing server row deletes clean local.
- 2026-08-23 Recipe `updatedAt` + `recipes` table migration. Recipe deletes now tombstone.
- 2026-08-23 Password reset on AuthView. Friendly auth errors.
- 2026-08-23 Item detail copy is "Flag as low below" — no notification lie.
- 2026-08-23 PrivacyInfo in the synchronized Saman/ group. Device family iPhone only.
- 2026-08-23 samaan-pantry-expert skill on main via #5.
- 2026-04-20 #2 Reorder writeback.
- 2026-04-19 THESIS.md + foundation.

## Active Work
- [ ] Owner: apply `supabase/migrations/003_recipes.sql` in the Supabase SQL editor
- [ ] Owner: deploy the `extract-recipe` and `delete-account` Edge Functions
- [ ] Owner: revoke the old Anthropic key in the Anthropic console
- [ ] Owner: create a pre-confirmed demo account for App Review (email confirmation is on)
- [ ] TestFlight, after the four above
- [ ] Household mode stays off (THESIS)

## Blockers
- Recipes pull no-ops until `003_recipes.sql` is applied in prod.
- Recipe capture and in-app account deletion fail until both Edge Functions are deployed.
- App Review cannot get past sign-up without the pre-confirmed demo account.

## Key Decisions
| Date | Decision | Reasoning | Affects |
|------|----------|-----------|---------|
| 2026-08-29 | Delete unreferenced files rather than quarantine them | The Xcode target uses `PBXFileSystemSynchronizedRootGroup`, so every file on disk compiles and ships. An orphan is not free | ItemRepository, PricesView |
| 2026-08-23 | Tombstones in UserDefaults, flushed before upload/pull | Deletes must survive a killed process | SyncManager, AppEnvironment.deleteRecord |
| 2026-08-23 | Local dirty wins over newer server | Avoid clobbering an in-flight edit | SyncReconcile |
| 2026-08-23 | iPhone only | UI is iPhone-designed; no iPad screenshots | pbxproj TARGETED_DEVICE_FAMILY |
| 2026-08-23 | No push alerts in v1 | Copy was lying; flagging as low is enough | ItemDetailView |
| 2026-04-20 | Restock UX: tap→sheet→stepper→confirm | Explicit commit, no lying to user | ReorderView |
| 2026-04-19 | SwiftData local + Supabase auth/sync | Native Apple, RLS for access | All models |
| 2026-04-19 | isDirty flag pattern for sync | Simple optimistic tracking | Models, SyncManager |

## Roadmap (do in order)
- [x] #2 Reorder writeback
- [x] Bidirectional sync + recipe sync + password reset + honest copy + iPhone-only
- [x] Live legal URLs
- [ ] Owner: recipes SQL, Edge Functions, Anthropic revoke, demo account
- [ ] TestFlight + README
- [ ] Household mode only after 500 WAU + 30% asking + sync stable

## Strategic decisions (do not reopen)
- Primary user: 25-35 diaspora adult, solo kitchen, single device
- Household/sharing: v2 only, conditions in THESIS.md
- Core loop: low → list → shop → bought → pantry updates
- Cuts approved: Prices tab (view deleted 2026-08-29), Scanner as top-level tab, Settings as tab
- Scanner stays inside Add Item. It is a data-entry method, not a destination
- Cultural specificity is the moat — no generic mode
- Not a recipe app. Recipes exist to feed the shopping list.

## Known issues (open)
- Deep-link password recovery is not in-app yet. No `CFBundleURLTypes`, no `onOpenURL`.
- `PantryListView` and `AddPantryView` are unreachable. Nothing presents `PantryListView`, and only it presents `AddPantryView`. Left in place on purpose: it is the only multi-pantry management UI written, so wiring it up is a real option. Delete it or wire it, do not keep ignoring it.
- `PantryListView` location filter is hardcoded to `["pantry","fridge","freezer"]`.
- `image_url` is modeled, migrated, and synced but nothing populates it. No photo picker, no Storage upload.
- Old Anthropic key must still be revoked in the provider account.

## Key Files
| File | Purpose |
|------|---------|
| THESIS.md | Product forcing function |
| Saman/App/RootView.swift | Auth gate + tab shell (Home, Pantry, Lists, Recipes) |
| Saman/App/AppEnvironment.swift | auth, modelContainer, syncNow(), deleteRecord() |
| Saman/Core/Services/SyncManager.swift | tombstones, upload dirty, pullAll |
| Saman/Core/Services/SyncReconcile.swift | dirty-wins / delete-if-missing |
| Saman/Core/Services/AuthService.swift | sign in/up, reset, delete-account, friendly errors |
| Saman/Core/Services/Config.swift | Supabase URL, anon key, legal URLs, Edge Function endpoints |
| Saman/PrivacyInfo.xcprivacy | Required nutrition labels |
| supabase/migrations/003_recipes.sql | Owner must apply |

## Architecture Notes
- The app target is a synchronized Xcode group. Any `.swift` file under `Saman/` compiles with no pbxproj entry, so unreferenced files still ship. Delete them, do not park them.
- persist pattern: model.markDirty() → context.save() → appEnv.syncNow()
- delete pattern: appEnv.deleteRecord(model, table:, id:) queues a tombstone then deletes locally
- Bare `context.delete` on a synced model is forbidden. It resurrects the row on the next pull. The only legitimate bare deletes are inside SyncManager's reconcile (server already dropped the row) and AppEnvironment's local wipe on sign-out.
- Secrets.xcconfig gitignored; placeholders only
- Item.isLow: quantity ≤ minimumQuantity (not strictly less than)
- Recipe AI goes through extract-recipe. Never Anthropic from the binary.
- RevenueCat entitlement id is `Saman Pro`, byte-for-byte with the dashboard. Do not "fix" the spelling.
- Voice for strings: practical, warm, culturally rooted. No em dashes. No pitch-deck words.

## Session Log
| Session | Date | Summary |
|---------|------|---------|
| 4 | 2026-08-29 | Verified legal URLs live (200), rewrote Active Work against live facts, deleted ItemRepository + PricesView |
| 3 | 2026-08-23 | Pull-sync, tombstones, password reset, iPhone-only, PrivacyInfo, honest low-stock copy |
| 2 | 2026-04-20 | Read THESIS, full codebase audit, wrote #2 reorder writeback fix |
| 1 | 2026-04-19 | First session — read project structure, bootstrapped MEMORY.md |
