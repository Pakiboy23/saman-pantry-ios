---
name: samaan-pantry-expert
description: Expert for Samaan Pantry (Pakiboy23/saman-pantry-ios) — native iOS pantry for one desi kitchen. Use for SwiftUI, SwiftData, Supabase sync, recipes-as-list-input, paywall, or App Store submission work. Thesis.md wins product arguments.
---

# Samaan Pantry expert

Native iOS. SwiftUI + SwiftData + Supabase + RevenueCat. Bundle `com.samanpantry.Saman`. Thesis: one person, one desi kitchen, one loop — low → list → shop → bought → pantry updates.

Not a meal planner, not a recipe app, not household sharing at v1.

## Current state (18 Sep 2026)

Already in repo: Pantry tab, mark-bought restock, in-app account deletion, recipe extraction via `extract-recipe` Edge Function (user JWT + 5/day quota), Anthropic key removed from the client, PrivacyInfo in `Saman/PrivacyInfo.xcprivacy`, StoreKit config, iOS 17 target, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), password reset on AuthView with `samaan://auth-callback`, pull-sync + tombstones, honest "Flag as low below" copy. Legal URLs are live: `samanpantry.com/privacy` and `/support` both return 200 (apex 307s to `www`), verified 29 Aug 2026. Keep them in App Store Connect and in `Config.swift`.

**Guest browse exists (#20).** Unsigned launch shows Home / Pantry / Lists / Recipes on local SwiftData. Auth is prompted only for Sync now, Extract Recipe (JWT), and Delete account. AuthView has "Not now". Do not restore a login wall.

**ReorderView is gone (#21).** Live loop is item detail → list → mark bought. Do not restore it.

**Build.** Xcode project is marketing `1.0`, `CURRENT_PROJECT_VERSION = 65` (#20). `1.0 (47)` was on TestFlight as of 30 Aug 2026. App Review rejected **64**; the repo bump to 65 is the next archive number. Do not invent a TestFlight listing for 65. Still not App Review ready — owner-console work remains. Do not submit until that is done.

## Non-negotiables (from THESIS.md)

- Mark bought must restock pantry. No lying to the user.
- Pantry and shopping list are one loop.
- Bidirectional sync before public launch.
- No feature unless it advances the core loop.
- The app never stops feeling like a desi product (Saag / Atta / Kohl, Cormorant + Noto Nastaliq Urdu).
- Household sharing stays off until 500 WAU + 30% asking + sync stable.

## Landmines

- Anon key in `Config.swift` is expected (RLS). Service role is not.
- Recipe AI goes through `Config.recipeExtractionEndpoint` with the **user JWT**, never the anon key as Bearer, never Anthropic from the binary. The function returns 402 `quota_exceeded` after 5 attempts / 24h (`recipe_extraction_events`). Owner must apply `004_recipe_extraction_events.sql` or every extract 500s.
- Account deletion goes through `delete-account` with the user JWT.
- Deletes go through `AppEnvironment.deleteRecord` so a tombstone is queued. Bare `context.delete` resurrects the row on the next pull.
- Prices is gone. The view was deleted 29 Aug 2026; do not rebuild it.
- `ReorderView` / `ReorderItemRow` / `RestockSheet` are gone. The live loop is item detail → list → mark bought. Do not restore ReorderView.
- Scanner is a data-entry method, not a destination — keep it inside Add Item.
- The app target is a synchronized Xcode group. Every `.swift` under `Saman/` compiles with no pbxproj entry, so an unreferenced file still ships. Delete dead code, do not park it.
- `PantryListView` and `AddPantryView` were deleted. Do not restore them; InventoryView is the pantry surface.
- Password recovery: `resetPasswordForEmail` uses `redirectTo: samaan://auth-callback`. Do **not** treat `.passwordRecovery` as sign-out. Owner must add that URL to Supabase Auth redirect URLs.
- RevenueCat entitlement id is `Saman Pro`, byte-for-byte with the dashboard. Do not "fix" it.
- Guest browse exists. Do not restore a login wall. `-UITesting` is a screenshot seed path, not a substitute for guest browse.

## Do not

- Submit while owner-console work (SQL, deploy, revoke key, demo account, redirect URL) is open.
- Grow recipe CRUD into a cookbook.
- Add household sharing "because the models already have it."
- Ship "Alert me when below" without a real notification.
- Restore ReorderView or a mandatory-account splash.

## Next repo work (order)

1. Owner: apply `003_recipes.sql` and `004_recipe_extraction_events.sql`, deploy `extract-recipe` and `delete-account`, revoke the old Anthropic key, create a pre-confirmed App Review demo account, add `samaan://auth-callback` to Auth redirect URLs.
2. Repo build is 1.0 (65). Historical TestFlight: 1.0 (47) as of 30 Aug 2026. Do not treat "then TestFlight" as outstanding.
3. Household mode only after the thesis gates.
