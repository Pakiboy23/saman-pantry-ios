# Project Memory
Last updated: 2026-04-19 | Session 1 | Branch: main
Memory health: 7/10

## Project Overview
Saman — iOS pantry & grocery management app. SwiftUI + SwiftData, Supabase backend (auth + sync). Very early stage (1 commit).

## Where We Left Off
- **Current task:** Project just scaffolded — reviewing structure at session start
- **Status:** Scaffolding complete, no active feature in progress
- **Next immediate step:** Define what to build next with the user
- **Open question:** Which feature to tackle first?

## Completed
- 2026-04-19 Initial scaffolding: models, features, auth, sync, design system

## Active Work
- [ ] TBD — awaiting user direction

## Blockers
- None known

## Key Decisions
| Date | Decision | Reasoning | Affects |
|------|----------|-----------|---------|
| 2026-04-19 | SwiftData for local persistence | Native Apple, no third-party ORM | All models |
| 2026-04-19 | Supabase for auth + sync | Quick backend, real-time capable | AuthService, SyncManager |
| 2026-04-19 | isDirty flag pattern for sync | Simple optimistic sync tracking | Item, SyncManager |
| 2026-04-19 | Cormorant Garamond + NotoNastaliqUrdu fonts | Bilingual (English + Urdu) brand | All UI |

## Key Files
| File | Purpose |
|------|---------|
| Saman/App/RootView.swift | Auth gate + tab shell (5 tabs) |
| Saman/App/AppEnvironment.swift | App-wide state: auth, modelContainer, syncNow() |
| Saman/Core/Models/Item.swift | Core model: quantity, min, barcode, expiry, isDirty |
| Saman/Core/Models/Pantry.swift | Pantry container for items |
| Saman/Core/Services/AuthService.swift | Supabase auth, session listening |
| Saman/Core/Services/SyncManager.swift | isDirty-based sync to Supabase |
| Saman/Core/Services/SupabaseClient.swift | Supabase singleton |
| Saman/Core/Design/SamanTheme.swift | Colors, fonts, design tokens |
| Saman/Core/Design/SamanComponents.swift | Shared UI components |
| Saman/Features/Inventory/ | InventoryView, AddItemView, AddPantryView, ItemDetailView, PantryListView |
| Saman/Features/Scanner/ | Barcode scanner + ProductLookupService |
| Saman/Features/ShoppingList/ | Shopping lists + items |
| Saman/Features/Auth/AuthView.swift | Sign-in screen |
| supabase/migrations/ | 001_initial_schema + 002_item_expiry_notes_image |

## Architecture Notes
- RootView gates on `appEnv.auth.hasCheckedInitialSession` to prevent auth flash on launch
- Tab bar: Home (Inventory), Reorder, Scan, Lists, Settings
- Cream palette: bg #FAF6EF, accent #C67E2A, muted #9A8472
- Secrets in Secrets.xcconfig (gitignored); Secrets.xcconfig.example for onboarding
- Item.isLow: quantity ≤ minimumQuantity; isExpiringSoon: < 7 days

## Session Log
| Session | Date | Summary |
|---------|------|---------|
| 1 | 2026-04-19 | First session — read project structure, bootstrapped MEMORY.md |
