---
name: samaan-pantry-expert
description: Expert for Samaan Pantry (Pakiboy23/saman-pantry-ios) — native iOS pantry for one desi kitchen. Use for SwiftUI, SwiftData, Supabase sync, recipes-as-list-input, paywall, or App Store submission work. Thesis.md wins product arguments.
---

# Samaan Pantry expert

Native iOS. SwiftUI + SwiftData + Supabase + RevenueCat. Bundle `com.samanpantry.Saman`. Thesis: one person, one desi kitchen, one loop — low → list → shop → bought → pantry updates.

Not a meal planner, not a recipe app, not household sharing at v1.

## Current state (Aug 2026)

Already in repo: Pantry tab, mark-bought restock, in-app account deletion, recipe extraction via `extract-recipe` Edge Function, Anthropic key removed from the client, PrivacyInfo, StoreKit config, iOS 17 target.

Still not submittable:

- `SyncManager` **uploads only**. Reinstall starts empty. Deletes do not propagate.
- No password reset on `AuthView`.
- `Config.swift` Privacy/Support URLs are TODO(owner) at samanpantry.com.
- Notification copy has no `UNUserNotificationCenter`.
- Recipes never sync (`isDirty` is meaningless).
- Old Anthropic key must still be **revoked** in the provider account.

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
- Prices tab is a stub. Scanner is a data-entry method, not a destination — keep it inside Add Item.
- Guest mode does not exist; App Review needs a pre-confirmed demo account or disabled email confirmation.

## Do not

- Submit this month.
- Grow recipe CRUD into a cookbook.
- Add household sharing "because the models already have it."
- Ship "Alert me when below" without a real notification.

## Next repo work (order)

1. Pull-sync + delete propagation (including recipes, or drop recipe `isDirty`).
2. Password reset.
3. Either wire notifications or delete the lying copy.
4. Then TestFlight — after owner deploys Edge Functions, rotates the AI key, and publishes legal URLs.
