# App Store Connect metadata, paste-ready (version 1.7)

Pulled from [`copy.md`](./copy.md), the copy source of truth. Change that file
first. Character counts are checked against Apple's limits.

Positioning: recipe first. The pantry and lists are the kitchen around the recipe.
No claims of grocery delivery, price comparison, nutrition, meal planning,
on-device or live transcription, or a lifetime plan.

---

## App name (30 max)
```
Samaan Pantry: Family Recipes
```
29. Live. Keep it.

## Subtitle (30 max)
```
Desi recipes from voice notes
```
29.

## Promotional text (170 max, no review needed)
```
Record a family recipe while they talk, in mixed Urdu, Hindi, Punjabi, and English. Andaza stays andaza. Then start a private cookbook for the whole family.
```
156.

## Keywords (100 max)
```
urdu,hindi,punjabi,pakistani,indian,cookbook,recorder,transcribe,nani,shopping list,grocery
```
91. Leaves out words already in the name and subtitle (samaan, pantry, family,
recipes, desi, voice, notes), since Apple indexes those.

## Description (4000 max)
```
Your family's recipes live in voice notes and memory. Samaan Pantry turns a recording into a recipe you keep, in the words they said. Andaza stays andaza.

Made for desi kitchens.

HIT RECORD WHILE THEY TALK
• Record at the stove or over the phone, for up to ten minutes. Or choose a voice note or audio file you already have.
• Code-switched is fine. Mixed Urdu, Hindi, Punjabi, and English come through.
• Samaan Pantry pulls out the ingredients and steps, from aloo keema to gajar halwa.

ANDAZA STAYS ANDAZA
• Vague amounts stay vague. No number gets guessed.
• The words they said stay with the recipe, so you can check what was meant.

PASTE A LINK OR THE WORDS
• Paste a YouTube video, a recipe site, or an Instagram caption.
• Or type or paste the recipe the way they say it.

ONE FAMILY, ONE COOKBOOK
• Start a private family cookbook with Samaan Pro and invite people with a link or a code. Joining is free.
• Members can read the recipes, add their own, leave notes, and keep a copy.
• The Community book holds recipes other cooks have shared. A recipe you make from a recording or pasted words is added there for signed-in cooks to read. Deleting the recipe takes it down. Recipes from links stay private unless you add them.

SEE WHAT'S LOW BEFORE YOU SHOP
• Track your staples and scan a barcode to add one.
• Send what is missing to a shopping list. Check an item off and the pantry updates.
• Everything syncs across your devices when you sign in.

FREE
• 5 recipe extractions for life. No card, no trial clock.
• Join family cookbooks and read the Community book.
• Unlimited pantry and shopping lists.
• Look around as a guest before you make an account.

SAMAAN PRO
• Unlimited recipe extractions.
• Start family cookbooks.
• $7.99 a month or $59.99 a year. Restore Purchases is in Settings.

PRIVACY
Recordings go through our server to ElevenLabs to be turned into text. Recipe text goes to Anthropic to pull out the ingredients and steps. We don't keep the audio on our server, and we don't sell your data. Delete your account and everything in it from Settings.

WHO BUILDS IT
Samaan Pantry is built by Syed Shariff, a solo developer who wanted to save the recipes that are one phone call away from being lost. Questions or ideas: haaris@samaan.tech.

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://www.samanpantry.com/privacy
```

## What's New (version 1.7, live)
`Voice recipes are more accurate. Recordings and audio files are now transcribed on our server, so long, mixed-language recipes come through in full. Plus new dark and tinted app icons.`

## What's New (version 1.6, shipped)
`Family cookbooks you invite people into, unlimited extracts on Samaan Pro, and a quieter first launch. Pantry and lists stay unlimited for everyone.`

Prior 1.0 line, kept for history: `First release. Track your pantry, keep a shopping list, and capture family recipes exactly how they were said.`

## App Review notes (critical — prevents the reviewer lockout)
```
Guest browse: first launch is a 3-page onboarding, then Home / Pantry / Lists /
Recipes (local SwiftData) without an account. Account is required only for Sync
now, Extract Recipe, community-book opt-in, family cookbooks, and Delete account.
AuthView has "Not now".

DEMO ACCOUNT (needed for extract / sync / delete; pantry UI does not require it):
  email: apple.review@samanpantry.com   password: kept only in App Store Connect (App Review Information)
This account is pre-confirmed; sign in directly, no email step needed.

If you prefer to create a new account, note that sign-up sends a confirmation
email that must be clicked before sign-in. Use the demo account to avoid this.

AI feature: "Capture a recipe" sends a recording, an audio file, pasted text,
or a link to our Supabase Edge Function. Audio is transcribed on the server by
ElevenLabs. We do not store the audio on our server, and the app deletes its
copy once the recipe comes back; ElevenLabs may keep request logs and
transcripts under its standard terms. The microphone is used only while the user
records a recipe. The function may read a public recipe page, a YouTube
title/description/captions, or an Instagram caption, then sends that text to
Anthropic unless the page already has a complete schema.org Recipe. No
third-party tracking.

Camera is used only for barcode scanning when adding an item.
Subscriptions are managed via RevenueCat; Restore Purchases is on the free
Settings surface and on the paywall (and Customer Center after purchase).
Privacy Policy, Terms, and Support are in Settings → LEGAL, on AuthView,
and on the paywall.
```

## Screenshots (6.9-inch, 1290 x 2796, dark)

Six dark frames built from real 1.7 screen recordings, no mockups. Headlines come
from the five features in `copy.md`. Upload in this order:

1. **Your family's recipes live in voice notes and memory.** Recipes, Yours shelf, each recipe with who it came from.
2. **Hit record while they talk.** Capture screen: Record a recipe, Choose a recording, paste a link, paste the words.
3. **Andaza stays andaza.** Review screen: each ingredient with the words that were said under it.
4. **The recipe, in their words.** The saved recipe: ingredients, steps, and notes.
5. **One family, one cookbook.** A family cookbook with its recipes.
6. **See what's low before you shop.** Home: Running low under the shopping lists.

The 1.6 set showed a live transcript and "Stop & save" while recording. 1.7 has
neither, so replace all six.

The PNGs are not in this repo. They show a real family recipe and its
transcribed phrases, so they were sent to Haaris directly. The source frames are
the 17 November 2026 screen recording. The only edits are cropping out the
status bar and the AssistiveTouch button, plus one scroll-gap join on frame 6.

## App Privacy label answers (must match PrivacyInfo.xcprivacy + real egress)
- Data collected: Name (the display name a user may set for family cookbooks), Email, User ID, Audio Data (recipe recordings and chosen audio files, sent to ElevenLabs for transcription; not stored on our server, though ElevenLabs may keep request logs and transcripts under its standard terms), Other User Content (pantry, recipes, recipe transcripts, pasted recipe text or links, family cookbook names, member notes, recipe snapshots shared into a family), Purchase History, Product Interaction (fixed screen names, fixed event names, anonymous install id, app version), Other Usage Data (app and device context the PostHog iOS SDK attaches: app version, OS, device model class, locale, timezone). No crash data or other diagnostics are collected (PostHog error tracking, session replay and autocapture are off). Invitee emails are not collected; invites are a code or link the user shares.
- Linked to you: name, email, user id, audio data, other user content, purchase history, product interaction, and other usage data. Signed-in HeyCatch events use the Supabase user id as the distinct id. The anonymous Supabase `events` row is still not tied to the account; the label is linked because the HeyCatch copy is. None of it is used for tracking.
- Purpose: App Functionality for name, email, user id, audio data, and other user content. Analytics as well as App Functionality for user id. App Functionality for purchase history (Apple has no separate "Purchases" purpose; processing purchases counts as App Functionality). Analytics for product interaction and other usage data.
- Third parties receiving data: Supabase (backend, plus the anonymous events row), HeyCatch (product analytics via the PostHog iOS SDK: fixed screen and event names, an app-generated anonymous id before sign-in, and the Supabase user id after sign-in — no recipe text, transcripts, audio, names, or emails), ElevenLabs (speech to text for recordings and audio files; may keep request logs and transcripts on a standard plan), Anthropic (recipe structuring, when the text is not already a schema.org Recipe), Google (YouTube video id only, and only if `YOUTUBE_API_KEY` is set), RevenueCat (purchases). The iOS share sheet sends the recipe to whatever destination the user picks.

## Category & age
- Primary: Food & Drink. Secondary: Lifestyle (matches the live listing).
- Age rating: 4+.
- Price: Free, with auto-renewable subscription (or non-consumable unlock — see Phase 4).
