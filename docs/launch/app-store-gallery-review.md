# Saman — App Store Gallery Review

**What this is:** the same kind of gallery critique we did for the Product Hunt launch, retargeted to the App Store product page and graded against Apple's own [Asset Best Practices](https://developer.apple.com/app-store/asset-best-practices/) + the current [screenshot](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) and [app preview](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications) specs. Reviewed against the real Saman UI and brand (Saag green, masala/amber accents, cream surfaces, Cormorant + Noto Nastaliq Urdu, bilingual).

**Reviewed:** 2026-11-17 · app icon (shipped), screenshots (none yet), app preview (none yet).

---

## The one thing to internalize

On the App Store, your "gallery" is **app icon → up to 3 app previews → up to 10 screenshots**, and **only the first ~3 screenshots (and up to 3 previews) show in search results** — that trio is your Product-Hunt-thumbnail equivalent. It has to land the pitch before anyone taps "more." For Saman the pitch is **"know what's in your desi kitchen, and keep your family's recipes."** Right now the gallery communicates *none* of that, because only the icon exists — and the icon is the weakest, most generic asset in the set.

**Scorecard**

| Asset | State | Grade | Headline |
|---|---|---|---|
| App icon | Shipped | **C** | Clean mark, but blank focal point, reads generic (not desi), no real dark variant |
| Screenshots | Not built | **—** | The whole sell. Needs a 5–6 frame story; first 3 are search-results |
| App preview | Not built | **—** | Optional for v1, high-leverage. The capture→list loop is tailor-made for it |
| Consistency / brand | — | **B potential** | The brand system is distinctive; the gallery just has to use it |

---

## 1. App icon — reviewed (it's the one real asset, so it gets the scrutiny)

The current icon is a flat **masala jar** — amber/honey body, cream label, on a near-black (InkKohl) background. Against Apple's bar ("memorable, unique, expressive of purpose, legible at every size"):

**What works**
- Clean, modern flat vector; single clear focal object, centered (Apple: "clear focal point… within the center to prevent clipping"). ✔
- On-brand palette (masala amber + ink). ✔
- 1024×1024, opaque RGB, no alpha — technically valid for the App Store icon. ✔

**What's weak — and fixable**
1. **The label is blank.** The brightest, most central element of the icon is an empty cream rectangle. At Spotlight / Settings / Home-Screen size it reads as "beige box inside amber box" — the focal point carries zero brand. *Fix:* put a single mark on the label — the Urdu glyph **س** (or **سامان**'s first letter), a devanagari **स**, or a haldi-yellow spice mound / chili. One glyph turns a generic jar into a branded one and survives down-scaling.
2. **It reads generic.** A plain jar is the default metaphor for *every* pantry app. Nothing says **desi** — which is the entire positioning moat. *Fix (bigger swing):* make it unmistakably a **masala dabba** (the round steel spice tin with 7 katoris) or the labeled-glyph jar above. The icon should telegraph "South Asian kitchen" at a glance, the same way the in-app Nastaliq does.
3. **No real dark-mode icon.** `AppIcon-1024-dark.png` is **byte-identical** to the light icon (verified: same md5). So iOS 18+ dark appearance just re-shows the light art — and because the art already has a dark background, it can look muddy on the system's dark icon backdrop. *Fix:* ship a true dark variant (brighter jar, slightly lifted background) or design the layers so the system supplies the backdrop. The **tinted** variant is at least a distinct file — eyeball it in Settings → "Tinted" to confirm the jar stays legible as a monochrome luminance map.
4. **Leftover Mac icon slots.** `Contents.json` still carries the multiplatform template's empty Mac sizes (16–512px) though this is an iOS-only app. Harmless but untidy — drop them.
5. **(Opportunity, not a blocker) Liquid Glass.** Apple's page now explicitly recommends **Icon Composer** to build a layered Liquid Glass icon from one design. A flat PNG is still accepted, but a layered icon is the current-era quality bar and would make the jar feel less static.

**Icon verdict:** keep the concept, fix the focal point and the desi signal, and give it a genuine dark variant. This is ~a half-day of design work and it's the single most-seen asset you own.

---

## 2. Screenshots — the gallery that actually sells (build this)

Apple's rules to design to: *show the app in use* (not accolades/CTAs), *sequence features into a cohesive story*, *short phrase overlays that enhance the visual rather than describe it*, *localize overlay text*, *legible at every size*, *4+ appropriate*, and **no pricing, URLs, copyright symbols, unverifiable claims/awards, or other-platform logos**.

### Recommended sequence — 6 frames, first 3 are the search-results trio

> Treatment for all: real screens on a clean simulator status bar (full battery, no carrier text, consistent time), framed on a **cream (Doodh/Malai)** background with a **short Saag-green headline** in Cormorant + a small Urdu accent word. One idea per frame. Keep the headline in the top third (safe area), device/screen in the lower two-thirds.

| # | Screen (real UI) | Headline (short, benefit-first) | Why it's here |
|---|---|---|---|
| **1** | **Pantry** full of desi staples with low-stock dots (atta out, haldi low, ghee stocked) | **"Know what's in your desi kitchen."** · سامان | Identity + daily value in one frame. Names like *atta, daal, haldi* instantly signal the niche. This is the thumbnail — make it the strongest. |
| **2** | **Recipe capture review** showing `haldi — andaza se` preserved next to **turmeric**, a vague amount shown as "—" | **"Keep the recipe in her exact words."** | The differentiator. No competitor does this. Emotional + unique = the reason to download. |
| **3** | **Shopping list** mid-shop, two items checked, one being tapped | **"Shop, check off — your pantry updates itself."** | The loop paying off. Shows the promise actually closes (the thing the app was failing to do before). |
| 4 | **Empty pantry → "Add desi staples"** (or Add Item sheet) | **"Start in seconds. One tap adds your staples."** | Kills the "this looks like work" objection; shows low-effort onboarding. |
| 5 | **Home dashboard** — Running low + active list together | **"Open it and see exactly what you need."** | The glanceable payoff; reinforces habit. |
| 6 *(optional)* | **Pro** value framed as capability | **"Unlimited recipe capture, synced across your phones."** | Only if it doesn't dilute. **No price, no "support development."** Benefit only. |

Notes tied to Apple's rules:
- **Frames 1–3 must stand alone** at thumbnail size in search — big legible headline, high-contrast screen, one idea each. Don't bury the hook in frame 5.
- **Overlay copy "enhances, not describes"**: "Know what's in your desi kitchen" (enhances) beats "A pantry list screen" (describes). ✔ in the table.
- **Real data, real screens.** Seed the pantry with the actual "desi staples" set and a real captured recipe before shooting — no Photoshop'd fake rows (2.3 Accurate Metadata).
- **Localize.** The app ships Nastaliq and targets a bilingual audience — localize the overlay text (and ideally the screenshots) for Urdu/Hindi if you list those locales. Apple explicitly calls this out.
- **Don't** put the app icon, award badges, "#1", star ratings, or `samanpantry.com` into any frame.

---

## 3. App preview (video) — optional for v1, but your loop is built for it

You can skip it for launch, but Saman's core loop is unusually demonstrable in 20 seconds, and previews **autoplay before screenshots and in search** — high leverage. If you do one:

**Storyboard (15–30s, silent-first, seamless loop):**
1. (0–3s) Pantry with low-stock dots — lead with identity/value (Apple: "compelling visuals in the first few seconds").
2. (3–8s) Tap **Capture a recipe**, paste a code-switched transcript.
3. (8–14s) Ingredients resolve — camera lingers on `haldi, andaza se → turmeric` (**this is the poster-frame moment, ~5s mark**).
4. (14–20s) Add to list → check items off → cut back to the pantry now updated. Loop.

**Rules:** must work **muted** (captions/text, not voiceover for meaning); **no quick cuts** (Apple explicitly warns against them — pace it slow); **loop with no visible jump**; poster frame defaults to the 5s frame, so engineer 5s to be the recipe "aha." Accepted iPhone size **886 × 1920** (portrait), 15–30s, ≤500 MB, H.264 .mp4/.mov, ≤30 fps.

---

## 4. Specs cheat-sheet (what you actually upload)

**Screenshots**
- Format **PNG or JPG, no alpha/transparency**, up to **10 per device size**, ≥1 required.
- **iPhone required:** one set at **1179 × 2556** (6.3" Dynamic Island "medium", e.g. iPhone 15/16) portrait. Upload the largest and App Store Connect **auto-scales down** if your UI is consistent — so you can get away with a single iPhone size.
- **iPad required *because* `TARGETED_DEVICE_FAMILY = "1,2"`:** one set at **2064 × 2752** (13"). ⚠️ **Decision point:** if you're not going to design and QA a real iPad layout + iPad screenshots, change the device family to iPhone-only (`"1"`) and this requirement disappears. Shipping iPad with iPhone-stretched UI and no iPad shots is a weak look and extra review surface. Recommendation stands from the launch review: **iPhone-only for v1.**

**App preview (if used):** iPhone **886 × 1920**, 15–30s, ≤500 MB, H.264, ≤30 fps, up to 3; poster frame = 5s by default.

**App icon:** 1024×1024, opaque, no alpha (already correct). Provide a **distinct** dark variant; consider Icon Composer for a layered version.

---

## 5. How to actually produce these (no Mac needed until the end)

This container is Linux, so the capture itself happens on your Mac, but the setup is scriptable:

1. **Decide iPad in/out** first (see §4). If out, flip `TARGETED_DEVICE_FAMILY` to `"1"` — one fewer full screenshot set to make.
2. **Seed realistic data** before shooting: run the app, tap **"Add desi staples"** (we built that), set a couple to low/out, create one shopping list mid-shop, and capture one recipe so `RecipeDetailView` renders real ingredients. (The recipe review screen needs either the deployed `extract-recipe` Edge Function *or* a previously-captured recipe — the stored `extractedJSON` re-renders without a live call, so seed one recipe once and screenshot the stored result.)
3. **Clean status bar:** use a consistent time / full battery (Xcode 15+ simulator shows a clean default; or `xcrun simctl status_bar`).
4. **Frame + caption:** drop the raw screenshots into a template (Figma, or `fastlane frameit`) with the cream background + Saag headline + Urdu accent. Keep headline in the top third.
5. **Localize** the caption layer for each listed locale.
6. Upload largest iPhone size (+ iPad if kept); let ASC scale.

---

## 6. Prioritized punch-list

**Do before submitting**
- [ ] **Icon:** put a brand mark on the blank label (Urdu glyph or spice), and ship a **real dark variant** (not a copy). *(Design, ~0.5 day)*
- [ ] **Screenshots:** build frames **1–3** at 1179×2556 — the search-results trio. Nothing else gates submission, but these three carry the conversion. *(Design + capture)*
- [ ] **iPad decision:** drop to iPhone-only *or* commit to iPad screenshots at 2064×2752. *(Eng config, 1 line)*

**High-value, not blocking**
- [ ] Screenshots 4–6 for the full story.
- [ ] A 20s app preview (poster frame at the recipe "aha").
- [ ] Remove leftover Mac icon slots from `Contents.json`.
- [ ] Localize the gallery for Urdu/Hindi if those locales are listed.

**Don't**
- [ ] No price/discount, URL, copyright symbol, award/"#1" claim, or other-platform logo in any asset. No fabricated data. All assets 4+.

---

*Companion to `docs/launch/app-store-metadata.md` (name/subtitle/keywords/description) — this doc covers only the visual gallery.*
