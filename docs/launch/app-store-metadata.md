# App Store Connect Metadata — draft copy

Positioning: a practical desi-kitchen pantry tool with a signature recipe-keepsake feature.
Stays inside what the build does. No claims of grocery automation, food-safety, nutrition,
"recognizes products," or meal planning. Lead with cultural specificity, not "AI."

> Decide the thesis-drift question (Phase 5) first. This copy assumes **pantry-first with
> recipe capture as the differentiator** (recommended). If you go recipe-first, swap the
> emphasis in the subtitle/description but keep the same honesty guardrails.

---

## App name (30 char max)
`Saman: Desi Pantry & Recipes`  (28)

Alt if "Saman" alone is the listing name: `Saman` + subtitle below.

## Subtitle (30 char max)
`Your kitchen, sorted` (20)
Alt: `Pantry, lists & family recipes` (30)

## Promotional text (170 char max — editable without review)
`Know what's in the cabinet, keep a running shopping list, and capture the recipes you actually cook — in the words they were said. Made for desi kitchens.` (152)

## Keywords (100 char max, comma-separated, no spaces)
`pantry,grocery,kitchen,inventory,shopping list,desi,south asian,recipe,masala,halal,staples,reorder` (99)

> Don't repeat words already in the name/subtitle (Apple indexes those). Drop "recipe" here
> if it's in the name. Consider locale variants: `atta,dal,ghee,patel brothers` test well for
> the niche but watch the 100-char budget.

## Description
```
Saman is a pantry app built for how desi kitchens actually run.

Know what you have. Track your staples — atta, daal, ghee, masalas, chai — and
see at a glance what's running low before you're standing at the store guessing.

Keep one running list. Add what you're low on, check it off as you shop, and let
your pantry stay up to date. No spreadsheet, no clutter.

Capture the recipes you actually cook. Paste a recipe the way it was told to you —
code-switched, "andaza se," a fistful of this — and Saman turns it into a clean
ingredient list you can add to your shopping in one tap. It never invents a number
your mother didn't say.

Made for the diaspora kitchen, not a generic grocery app.

Saman is free to use. Saman Pro (optional) unlocks unlimited recipe capture and
sync across your devices.

— Your data is yours. Delete your account and everything in it any time, in the app.
```

> The last two lines pre-empt reviewer questions about subscription + deletion. Keep them
> accurate to whatever you actually ship (don't mention sync until pull-sync exists).

## What's New (version 1.0)
`First release. Track your pantry, keep a shopping list, and capture family recipes exactly how they were said.`

## App Review notes (critical — prevents the reviewer lockout)
```
DEMO ACCOUNT (email confirmation is required to sign in):
  email: review@samanpantry.com   password: <set a real one>
This account is pre-confirmed; sign in directly, no email step needed.

If you prefer to create a new account, note that sign-up sends a confirmation
email that must be clicked before sign-in. Use the demo account to avoid this.

AI feature: "Capture a recipe" sends the pasted transcript to Anthropic via our
Supabase Edge Function to structure it into ingredients. No third-party tracking.

Camera is used only for barcode scanning when adding an item.
Subscriptions are managed via RevenueCat; Restore Purchases is in Settings and on
the paywall. Privacy Policy and Terms links are in Settings > About and on the paywall.
```

## Screenshot shot-list (show real use, not empty UI)
1. Pantry with desi staples + low-stock dots (haldi low, atta out) — the daily value.
2. Recipe capture review screen showing "haldi — andaza se" preserved next to "turmeric."
3. Shopping list mid-checkout, a couple items checked off.
4. Home dashboard: running low + active list together.
5. (Optional) Paywall framed around "unlimited recipe capture + sync," not "support development."

Caption each with the benefit ("See what's low before you shop", "Your mother's exact words, kept").

## App Privacy label answers (must match PrivacyInfo.xcprivacy + real egress)
- Data collected: Email, User ID, Other User Content (pantry/recipes), Purchase History.
- All "linked to you," none "used for tracking."
- Purpose: App Functionality (+ Purchases for purchase history).
- Third parties receiving data: Supabase (backend), Anthropic (recipe structuring), RevenueCat (purchases).

## Category & age
- Primary: Food & Drink. Secondary: Productivity.
- Age rating: 4+.
- Price: Free, with auto-renewable subscription (or non-consumable unlock — see Phase 4).
