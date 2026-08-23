# Project Memory
Last updated: 2026-08-23 | Session 3 | Branch: ops/sync-reset-legal
Memory health: 8/10

## Project Overview
Samaan — iOS pantry app for one desi kitchen. SwiftUI + SwiftData + Supabase `mcknboqvblbonmaebmjg` + RevenueCat. Product company: Saman Technologies LLC. Bundle `com.samanpantry.Saman`. THESIS.md wins product arguments.

## Where We Left Off
- **Current task:** Bidirectional sync, password reset, honest low-stock copy, iPhone-only, PrivacyInfo, legal URLs.
- **Status:** Code is on `ops/sync-reset-legal`. Not on TestFlight. Recipes table does not exist in prod until owner applies `supabase/migrations/003_recipes.sql`.
- **Next immediate step:** Owner applies the recipes migration, deploys `extract-recipe` and `delete-account` Edge Functions, revokes the old Anthropic key, then TestFlight.
- **Open question:** Deep-link recovery after the reset email. `resetPasswordForEmail` sends the mail; tapping the link still depends on the Supabase Site URL.

## Completed
- 2026-08-23 Pull-sync + tombstones. Upload dirty, then pull. Local dirty wins. Missing server row deletes clean local.
- 2026-08-23 Recipe `updatedAt` + `recipes` table migration. Recipe deletes now tombstone.
- 2026-08-23 Password reset on AuthView. Friendly auth errors.
- 2026-08-23 Item detail copy is "Flag as low below" — no notification lie.
- 2026-08-23 PrivacyInfo in the synchronized Saman/ group. Device family iPhone only.
- 2026-08-23 samaan-pantry-expert skill on main via #5.
- 2026-04-20 #2 Reorder writeback.
- 2026-04-19 THESIS.md + foundation.

## Active Work
- [ ] Owner: apply `003_recipes.sql` in the Supabase SQL editor
- [ ] Owner: confirm extract-recipe + delete-account are deployed; rotate Anthropic key
- [ ] Owner: merge saman-landing so samanpantry.com/privacy and /support return 200
- [ ] Demo account for App Review (email confirmation currently required)
- [ ] TestFlight after the four above
- [ ] Household mode stays off (THESIS)

## Blockers
- Recipes pull will no-op until the table exists in prod.
- Legal URLs 404 until saman-landing ships rewrites.

## Key Decisions
| Date | Decision | Reasoning | Affects |
|------|----------|-----------|---------|
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
- [ ] Owner: Edge Functions, recipes SQL, Anthropic revoke, live legal URLs
- [ ] TestFlight + README
- [ ] Household mode only after 500 WAU + 30% asking + sync stable

## Strategic decisions (do not reopen)
- Primary user: 25-35 diaspora adult, solo kitchen, single device
- Household/sharing: v2 only, conditions in THESIS.md
- Core loop: low → list → shop → bought → pantry updates
- Cuts approved: Prices tab, Scanner as top-level tab, Settings as tab
- Cultural specificity is the moat — no generic mode
- Not a recipe app. Recipes exist to feed the shopping list.

## Known issues (open)
- Deep-link password recovery is not in-app yet
- PantryListView filter hardcoded ["pantry","fridge","freezer"]
- PantryListView showManage sheet unreachable
- ItemRepository dead scaffolding, never injected
- Prices tab is an orphaned stub
- Old Anthropic key must still be revoked in the provider account

## Key Files
| File | Purpose |
|------|---------|
| THESIS.md | Product forcing function |
| Saman/App/RootView.swift | Auth gate + tab shell |
| Saman/App/AppEnvironment.swift | auth, modelContainer, syncNow(), deleteRecord() |
| Saman/Core/Services/SyncManager.swift | tombstones, upload dirty, pullAll |
| Saman/Core/Services/SyncReconcile.swift | dirty-wins / delete-if-missing |
| Saman/Core/Services/AuthService.swift | sign in/up, reset, delete-account, friendly errors |
| Saman/Core/Services/Config.swift | Supabase URL, anon key, legal URLs, Edge Function endpoints |
| Saman/PrivacyInfo.xcprivacy | Required nutrition labels |
| supabase/migrations/003_recipes.sql | Owner must apply |

## Architecture Notes
- persist pattern: model.markDirty() → context.save() → appEnv.syncNow()
- delete pattern: appEnv.deleteRecord(model, table:, id:) queues a tombstone then deletes locally
- Secrets.xcconfig gitignored; placeholders only
- Item.isLow: quantity ≤ minimumQuantity (not strictly less than)
- Recipe AI goes through extract-recipe. Never Anthropic from the binary.
- Voice for strings: practical, warm, culturally rooted. No em dashes. No pitch-deck words.

## Session Log
| Session | Date | Summary |
|---------|------|---------|
| 3 | 2026-08-23 | Pull-sync, tombstones, password reset, iPhone-only, PrivacyInfo, honest low-stock copy |
| 2 | 2026-04-20 | Read THESIS, full codebase audit, wrote #2 reorder writeback fix |
| 1 | 2026-04-19 | First session — read project structure, bootstrapped MEMORY.md |
