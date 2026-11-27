# Marketing assets

Launch assets for Samaan Pantry, with the sources and scripts that rebuild them. Every
generated file below is committed as reviewed, and the scripts re-render it identically.

Copy rules used throughout: recipe capture leads (not the pantry), and no gendered copy
(no "her", "Ammi", "Mom"). App Store assets follow Apple's
[asset best practices](https://developer.apple.com/app-store/asset-best-practices/):
no prices, URLs, awards or other-platform logos, and key content inside the safe area.

## What's here

| File | Use | Spec |
|---|---|---|
| `app-store/screenshots/SamaanPantry-01-record-1179x2556.png` | Screenshot 1, the first image in search results | 1179×2556 PNG, no alpha |
| `app-store/screenshots/SamaanPantry-02-andaza-1179x2556.png` | Screenshot 2 | same |
| `app-store/screenshots/SamaanPantry-03-pantry-1179x2556.png` | Screenshot 3 | same |
| `app-store/creative/Header-3840x1646.png` | App Store Connect → Header and Search Results → **Header** | 21:9, sRGB, no alpha |
| `app-store/creative/SearchResults-3840x2560.png` | App Store Connect → Header and Search Results → **Search Results** | 3:2, sRGB, no alpha |
| `launch-video/Samaan-Pantry-ProductHunt.mp4` | Product Hunt video (upload to YouTube as Unlisted, then paste the link) | 40s, 1920×1080, H.264, silent for now |

The three screenshots came from the "Samaan Pantry: App Store gallery" design canvas (v1
row). Screenshot 1 has "Ammi's" removed.

## Launch video

Ten shots of exactly 4.0s on a **120 BPM** grid, so a 120 BPM track lands a cut every 8 beats:

| Time | Shot | Source |
|---|---|---|
| 0–4s | Brand open | animated (`src/shots.html?shot=brand`) |
| 4–8s | **Tap Capture a recipe.** | real footage |
| 8–12s | **Just talk it through.** Record, then "Listening." | real footage |
| 12–16s | **However you say it.** "Theen packet frozen bhindi…" | animated |
| 16–20s | **Words in. Recipe out.** Real spinners, sped up | real footage |
| 20–24s | **Andaza stays andaza.** Red chili kept as said | animated |
| 24–28s | **Check it. Save it.** Real Review and "Ingredients saved" | real footage (Nov 17, build 204) |
| 28–32s | **Ready to cook.** The real recipe | `src/assets/bhindi-recipe-clean.png` ("from Mom" removed) |
| 32–36s | **One book, the whole family.** | animated, made-up "Khan Family" |
| 36–40s | End card, "Free on the App Store" | animated |

The animated shots use the app's real dark UI. The real-footage shots use the same phone
frame and caption layout.

**Raw recordings are not in the repo.** They show personal file names, the real family book,
the owner's name and voice. To rebuild, place them in `launch-video/footage/` (gitignored):

- `old-build-capture.mp4`: 1206×2622. The cut uses only 2.0–11.25s (home → Capture → Record →
  "Listening") and 42.0–53.8s (spinners). Everything after that is an old build's bad output.
- `nov17-bhindi-run.mov`: the build-204 run. The cut uses only 20.9–24.6s (Review, with the FROM
  field empty) and 30.7–32.9s ("Ingredients saved"). Skip 3–7s (file picker), 25–30s ("Mom"),
  and 51s onward (family book with real names).

## Rebuild

Needs Node with `playwright` (Chromium), `ffmpeg`, and ImageMagick (`convert`, `identify`).

```sh
cd marketing
./scripts/fetch-fonts.sh        # Cormorant Garamond, IBM Plex Mono, Noto Nastaliq Urdu → fonts/ (gitignored)
./scripts/render-creative.sh    # → app-store/creative/*.png
./scripts/render-video.sh       # → launch-video/Samaan-Pantry-ProductHunt.mp4 (about 6 minutes)
MUSIC=track.mp3 ./scripts/render-video.sh   # same, scored: fade in 0.5s, fade out over the last 2.5s
```

Renders are deterministic: `scripts/render.cjs` pauses every CSS animation and seeks it frame
by frame, so output doesn't depend on machine speed.

## Open items

- **Music.** The video is silent. Pick a ~120 BPM track (YouTube Studio's Audio Library is
  cleared for YouTube) and rebuild with `MUSIC=`.
- **Footage resolution.** `nov17-bhindi-run.mov` was shared at 296×640, so the "Check it. Save it."
  shot is softer than the rest. Swap in the original full-resolution recording if it turns up.
- **Gendered words in extracted recipes.** One older extraction wrote "speaker noted she would…"
  in its steps. The fix is a no-gendered-pronouns rule in
  `supabase/functions/extract-recipe/prompts.ts`, which has to pass `scripts/recipe-eval.ts`
  before it merges.
