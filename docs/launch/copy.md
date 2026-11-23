# Samaan Pantry copy: source of truth (version 1.7)

Every public surface pulls from this file: the App Store listing and screenshots,
samanpantry.com, the Pantry section of samaan.tech, and the Product Hunt page,
gallery, and video. When the app changes, change this file first, then the
surfaces.

Checked against `main` at c1a6da2 on 21 November 2026.

## Names

| Thing | Use | Notes |
|---|---|---|
| Product | Samaan Pantry | Double a. Never "Saman Pantry" in display copy. |
| App Store name | Samaan Pantry: Family Recipes | Live. 29 of 30 characters. |
| Domain | samanpantry.com | Single a. URLs only. |
| Legal entity | Saman Technologies LLC | Footers, terms, privacy. |
| Studio | Samaan Technologies, samaan.tech | |
| Paid plan | Samaan Pro | |
| Urdu mark | سامان | "Samaan is the Urdu word for provisions." |
| Shelves | Yours, Families, Community | The tab labels in Recipes. |
| Private books | family cookbook | Lower case in running text. |
| Public book | the Community book | Not "family book" and not "shared family book". |

## Positioning

Recipe first. The pantry and lists are the kitchen around the recipe, not the
lead. This supersedes the pantry-first shot list in `app-store-gallery-review.md`.
THESIS.md still says pantry first and needs a decision from Haaris.

## Lines

- **Headline:** Your family's recipes live in voice notes and memory.
- **One-liner:** Samaan Pantry turns a recording into a recipe you keep, in the words they said.
- **Kicker:** Made for desi kitchens.
- **Closing line:** Start with the recipe you'd hate to lose.
- **Why:** A recipe kept in memory is one phone call away from being lost.

## The five features

Same order and wording on every surface. The headline is the slide, screenshot,
or section title. The subhead is the line under it.

1. **Hit record while they talk.**
   At the stove or over the phone, for up to ten minutes. Code-switched, andaza and all.
2. **Andaza stays andaza.**
   Vague amounts stay vague. No number gets guessed, and the words they said stay with the recipe.
3. **Paste a link or the words.**
   A YouTube video, a recipe site, or an Instagram caption. Or type it the way they say it.
4. **One family, one cookbook.**
   Start a private family cookbook and invite people with a link or a code. Joining is free.
5. **See what's low before you shop.**
   Track your staples, scan a barcode to add one, and send what is missing to a shopping list.

## Facts the copy can state

- Records up to 10 minutes. Recording stops at 10:00.
- Or choose an audio file, such as a voice note.
- Recordings and audio files are turned into text on our server, not on the iPhone.
- Typed or pasted text can mix Urdu, Hindi, Punjabi, and English. Recordings can too.
- Links: YouTube, recipe sites, Instagram captions. If an Instagram caption can't be read, the app asks for the caption text.
- The transcript stays with the recipe.
- Missing ingredients go to a shopping list in one tap. Checking an item off updates the matching pantry item.
- Pantry: barcode scan, a minimum to keep on hand, Running low on Home.
- Guest: pantry, lists, and recipes work without an account. Extraction, sync, family cookbooks, and the Community book need a signed-in account.
- iPhone only, iOS 17 or later. No Android, no date.
- Account deletion is in Settings.

## Family cookbooks and the Community book

- Starting a family cookbook needs Samaan Pro. Joining one is free.
- Invite by link or code. Invites last 7 days.
- Members can read recipes, add their own, leave notes, and save a copy. All free.
- If the owner's Samaan Pro lapses, the family keeps working.
- **The Community book is public to signed-in users, and opt-in.** Every recipe
  starts private, however it was captured. The owner taps "Share to Community"
  to add one: its title, who it is from, the ingredients, and the steps (plus the
  source link for a link recipe). The recording and transcript never go on the
  card. "Remove from Community" takes the card down and keeps the recipe.
  The card's "added by" label is the owner's display name, or the part of their
  email address before the @ if they haven't set one
  (migration 20261123000000_community_opt_in).

Approved wording for the Community book:

> The Community book holds recipes other cooks have chosen to share. Your
> recipes stay private until you share one, and you can take it back out any
> time.

Captured recipes are private by default. The server side is live (migration
applied 23 Nov 2026). Only use this wording publicly once 1.8, the build with
the Share to Community toggle, is released. 1.7 still labels its recordings
"in the family book" even though they now stay private.

## Pricing

- **Free:** $0. 5 recipe extractions for life. No card, no trial clock. Join family
  cookbooks. Read the Community book. Unlimited pantry and lists.
- **Samaan Pro:** unlimited recipe extractions, start family cookbooks, keep every
  recipe you save. $7.99 a month or $59.99 a year. The yearly plan saves 37%.
- Purchases are handled by Apple. Restore Purchases is in Settings.
- No lifetime plan. Do not mention one.
- The in-app paywall says "save 38%". The math is 37.4%. Fix the app string.

## Privacy line

> Recordings go through our server to ElevenLabs to be turned into text. Recipe
> text goes to Anthropic to pull out the ingredients and steps. We don't keep the
> audio on our server, and we don't sell your data.

Long form lives at samanpantry.com/privacy.

## Never claim

Grocery delivery, Instacart, price comparison, push alerts, nutrition, meal
planning, on-device transcription, live transcription while you record, a
lifetime plan, "coming soon" family cookbooks, Android.

## Product Hunt

- **Name:** Samaan Pantry
- **Tagline (54 of 60):** Turn family voice notes into recipes you can cook from
- **Description (234 of 260):** Your family's recipes live in voice notes and memory. Record someone at the stove or on the phone, in mixed Urdu, Hindi, Punjabi, and English. Samaan Pantry turns it into ingredients and steps, and andaza stays andaza. Free on iPhone.
- **Gallery:** V2-Problem, V2-Record, V2-Andaza, V2-Family, V2-Pantry (dark, 1270x760).
- **Video:** 26-second 1.7 cut. YouTube link, unlisted or public.
- **Pricing tag:** Free options (in-app purchase).

### Maker comment

> My family's recipes live in voice notes. Long ones, in three languages, with
> "thora sa" where the measurement should be. Every recipe app I tried wanted me
> to type them up and pick a number.
>
> Samaan Pantry lets you hit record while someone talks you through a dish, for
> up to ten minutes. It pulls out the ingredients and steps and leaves andaza as
> andaza. Then you can start a private family cookbook and invite people with a
> code.
>
> Free to start, 5 recipes for life. Samaan Pro is $7.99 a month or $59.99 a year.
>
> I'd love to hear which recipe you'd save first.

## Open items for Haaris

1. Community is opt-in (PR #98, 1.8). `20261123000000_community_opt_in.sql`
   was applied in production on 23 Nov 2026: the 6 existing cards stayed up,
   and new recipes from any app version now save private. 1.8 (218) is in
   TestFlight. Still to do: release 1.8 and make sure it is the version live
   for Product Hunt. Until then, 1.7 shows new recordings as "in the family
   book" and has no way to share them.
2. App strings that drift from this file: the paywall's "save 38%", the Home
   card's "Paste a transcript to extract ingredients", and "family book" for
   what the tab calls Community.
3. The App Store seller line shows Syed Shariff. The website says Haaris Shariff.
4. THESIS.md says pantry first. Every public surface now says recipe first.
