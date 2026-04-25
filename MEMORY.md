# Project Memory
Last updated: 2026-04-20 | Session 2 | Branch: reorder-writeback
Memory health: 9/10

## Project Overview
Saman — iOS pantry app for Pakistani/South Asian diaspora. SwiftUI + SwiftData + Supabase. Product company: Saman Technologies LLC. Active v1 development.

## Where We Left Off
- **Current task:** #2 Reorder writeback fix — complete, on branch `reorder-writeback`
- **Status:** 2 commits pushed locally, awaiting user manual test then PR merge
- **Next immediate step:** User tests the Reorder flow in Xcode (see test steps below), then merges PR. After merge, start #3 (loop unification design doc).
- **Open question:** None — #3 scope is defined in THESIS and roadmap.

## Manual test for #2 (do before merging PR)
1. Item "Atta", quantity 0, minimumQuantity 2
2. Reorder tab → item appears with `+` icon
3. Tap row → sheet opens, stepper defaults to **3** (max(2-0+1,1))
4. "New total: 3 unit" shows live
5. Confirm → item leaves list
6. Item detail → quantity shows 3
7. Edge: set amount to 2, confirm → item stays (quantity=2=minimum, still low)

## Completed
- 2026-04-20 #2 Reorder writeback: sheet+stepper UX, commits quantity, branch `reorder-writeback`
- 2026-04-20 Foundation commit: full architecture (models, services, features, design system) now in git
- 2026-04-19 THESIS.md written to repo root
- 2026-04-19 Initial scaffolding: models, features, auth, sync, design system

## Active Work
- [ ] User tests #2 in Xcode and merges `reorder-writeback` PR
- [ ] #3: Write docs/loop-unification.md design doc (no code yet)

## Blockers
- None

## Key Decisions
| Date | Decision | Reasoning | Affects |
|------|----------|-----------|---------|
| 2026-04-20 | Restock UX: tap→sheet→stepper→confirm | Explicit commit, no lying to user | ReorderView, SamanComponents |
| 2026-04-20 | Smart default = max(min-qty+1, 1) | One confirm gets item above threshold | RestockSheet init |
| 2026-04-20 | Items leave Reorder list naturally post-commit | No separate "Restocked" section needed | ReorderView |
| 2026-04-20 | ReorderItemRow API: onTap only, no isChecked | Checked state removed, list shrinks on commit | SamanComponents |
| 2026-04-19 | SwiftData for local persistence | Native Apple, no third-party ORM | All models |
| 2026-04-19 | Supabase for auth + sync | Quick backend, real-time capable | AuthService, SyncManager |
| 2026-04-19 | isDirty flag pattern for sync | Simple optimistic sync tracking | Item, SyncManager |
| 2026-04-19 | Cormorant Garamond + NotoNastaliqUrdu fonts | Bilingual (English + Urdu) brand | All UI |

## Roadmap (do in order, stop after each for user review)
- [x] #2 Reorder writeback fix (branch: reorder-writeback, pending merge)
- [ ] #3 Loop unification design doc (docs/loop-unification.md, no code)
- [ ] #4 Bidirectional sync + secrets hygiene
- [ ] #5 Strip nav and dead code (tab cuts, PantryListView fixes, ItemRepository decision)
- [ ] #6 TestFlight + README

## Strategic decisions (do not reopen)
- Primary user: 25-35 diaspora adult, solo kitchen, single device
- Household/sharing: v2 only, conditions in THESIS.md
- Core loop: low → list → shop → bought → pantry updates
- Tab target: Pantry, List (Reorder may fold into Pantry in #3)
- Cuts approved: Prices tab, Scanner as top-level tab, Settings as tab
- Cultural specificity is the moat — no generic mode

## Known issues (open)
- Sync upload-only, no pull (#4)
- Supabase anon key hardcoded in Config.swift (#4)
- PantryListView filter hardcoded ["pantry","fridge","freezer"] (#5)
- PantryListView showManage sheet unreachable (#5)
- ItemRepository dead scaffolding, never injected (#5)
- Prices tab is orphaned stub (#5)
- SamanTests/SamanUITests empty templates (#4)

## Key Files
| File | Purpose |
|------|---------|
| THESIS.md | Product forcing function — answer every decision here first |
| Saman/App/RootView.swift | Auth gate + tab shell |
| Saman/App/AppEnvironment.swift | auth, modelContainer, syncNow() |
| Saman/Core/Models/Item.swift | quantity, min, barcode, expiry, isDirty, isLow |
| Saman/Core/Design/SamanTheme.swift | Colors, fonts, spacing, button styles |
| Saman/Core/Design/SamanComponents.swift | Shared components incl. ReorderItemRow |
| Saman/Core/Services/SyncManager.swift | isDirty upsert to Supabase (upload-only) |
| Saman/Core/Services/Config.swift | Supabase URL + anon key (hardcoded — fix in #4) |
| Saman/Features/Reorder/ReorderView.swift | Restock sheet + writeback (fixed in #2) |

## Architecture Notes
- persist pattern: item.markDirty() → context.save() → appEnv.syncNow()
- Secrets.xcconfig gitignored; use Secrets.xcconfig.example for onboarding
- Item.isLow: quantity ≤ minimumQuantity (not strictly less than)
- No new dependencies without asking. Only Supabase + VisionKit in use.
- Voice for strings: practical, warm, culturally rooted. No em dashes. No pitch-deck words.

## Session Log
| Session | Date | Summary |
|---------|------|---------|
| 2 | 2026-04-20 | Read THESIS, full codebase audit, wrote #2 reorder writeback fix |
| 1 | 2026-04-19 | First session — read project structure, bootstrapped MEMORY.md |
