---
name: samaan-pantry-expert
description: Expert for Samaan Pantry (Pakiboy23/saman-pantry-ios) — native iOS pantry for one desi kitchen. Use for SwiftUI, SwiftData, Supabase sync, recipes-as-list-input, paywall, or App Store submission work. Thesis.md wins product arguments.
---

# Samaan Pantry expert

Native iOS. SwiftUI + SwiftData + Supabase + RevenueCat. Bundle `com.samanpantry.Saman`. Thesis: one person, one desi kitchen, one loop — low → list → shop → bought → pantry updates.

Not a meal planner, not a recipe app, not household sharing at v1.

## Current state (29 Aug 2026)

Already in repo: Pantry tab, mark-bought restock, in-app account deletion, recipe extraction via `extract-recipe` Edge Function, Anthropic key removed from the client, PrivacyInfo in `Saman/PrivacyInfo.xcprivacy`, StoreKit config, iOS 17 target, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), password reset on AuthView, pull-sync + tombstones, honest "Flag as low below" copy. Legal URLs are live: `samanpantry.com/privacy` and `/support` both return 200 (apex 307s to `www`), verified 29 Aug 2026. Keep them in App Store Connect and in `Config.swift`.

Still not submittable:

- Owner must apply `supabase/migrations/003_recipes.sql`. Without it, recipe pull no-ops.
- Owner must deploy `extract-recipe` and `delete-account`, and revoke the old Anthropic key.
- App Review needs a pre-confirmed demo account (email confirmation is on).

## Non-negotiables (from THESIS.md)

- Reorder must actually restock.
- Pantry and shopping list are one loop.
- Bidirectional sync before public launch.
- No feature unless it advances the core loop.
- The app never stops feeling like a desi product (Saag / Atta / Kohl, Cormorant + Noto Nastaliq Urdu).
- Household sharing stays off until 500 WAU + 30% asking + sync stable.

## Landmines

- Anon key in `Config.swift` is expected (RLS). Service role is not.
- Recipe AI goes through `Config.recipeExtractionEndpoint`, never Anthropic from the binary.
- Account deletion goes through `delete-account` with the user JWT.
- Deletes go through `AppEnvironment.deleteRecord` so a tombstone is queued. Bare `context.delete` resurrects the row on the next pull.
- Prices is gone. The view was deleted 29 Aug 2026; do not rebuild it.
- Scanner is a data-entry method, not a destination — keep it inside Add Item.
- The app target is a synchronized Xcode group. Every `.swift` under `Saman/` compiles with no pbxproj entry, so an unreferenced file still ships. Delete dead code, do not park it.
- `PantryListView` and `AddPantryView` are still unreachable. Wire them up or delete them, but know they are dead today.
- RevenueCat entitlement id is `Saman Pro`, byte-for-byte with the dashboard. Do not "fix" it.
- Guest mode does not exist.

## Do not

- Submit this month.
- Grow recipe CRUD into a cookbook.
- Add household sharing "because the models already have it."
- Ship "Alert me when below" without a real notification.

## Next repo work (order)

1. Owner: recipes SQL, Edge Functions, Anthropic revoke, pre-confirmed App Review demo account.
2. Then TestFlight.
3. Household mode only after the thesis gates.
