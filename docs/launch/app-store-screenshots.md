# App Store screenshots (Mac Simulator)

Capture **real** iPhone Simulator PNGs for the shot-list in
[`app-store-metadata.md`](./app-store-metadata.md). This path does not invent
marketing images. If you are not on a Mac with Xcode, the script exits
(or `--dry-run`s) without writing PNGs.

## Run (macOS + Xcode)

```sh
./scripts/capture-app-store-screenshots.sh
```

Default device: **iPhone 16 Pro**, or the newest available `iPhone * Pro` if
that name is not installed. Override with `--device "iPhone 16 Pro Max"` if
App Store Connect asks for the 6.9" size.

Output:

```
artifacts/app-store-screenshots/01-pantry.png
artifacts/app-store-screenshots/02-recipe-review.png
artifacts/app-store-screenshots/03-shopping-list.png
artifacts/app-store-screenshots/04-home.png
artifacts/app-store-screenshots/05-paywall.png
artifacts/app-store-screenshots/MANIFEST.md
```

`artifacts/` is gitignored. Commit the script and this doc, not the PNGs.

### Flags

| Flag | Meaning |
|------|---------|
| `--dry-run` | Print the plan. Safe on Linux / CI. |
| `--device NAME` | Simulator device name. |
| `--skip-paywall` | Skip the optional fifth shot. |
| `--uitest` | Also run `SamanUITests/AppStoreScreenshotUITests`. |
| `--demo-account` | With `--uitest`, sign in using env credentials instead of `-UITesting`. |

## Auth: `-UITesting` vs demo account

Auth normally blocks the tab shell. There is still **no guest mode**.

**Default (recommended for screenshots):** the script launches with:

```
-UITesting -ScreenshotSeed -ScreenshotScene <pantry|recipeReview|shoppingList|home|paywall>
```

`-UITesting` is a launch-argument bypass used only by this script and the
screenshot UI tests. It:

- treats the session as signed in (no Supabase call)
- uses an in-memory SwiftData store
- seeds a desi kitchen that matches the shot-list (atta **out**, haldi **low**,
  Patel Brothers list mid-checkout, Chicken Karahi with `haldi — andaza se`)
- skips pull/push sync so the seed is not uploaded

**Demo account:** set `SAMAN_DEMO_EMAIL` and `SAMAN_DEMO_PASSWORD` to the
pre-confirmed App Review account from `app-store-metadata.md`, then:

```sh
SAMAN_DEMO_EMAIL=review@samanpantry.com \
SAMAN_DEMO_PASSWORD='…' \
./scripts/capture-app-store-screenshots.sh --uitest --demo-account
```

`simctl` cannot type into AuthView, so PNG capture still uses `-UITesting`.
`--demo-account` only changes the XCUITest sign-in path.

Already signed in on a Simulator and want live data instead of the seed:

```sh
# Not supported by the script on purpose — relaunch without -UITesting and
# capture by hand, or keep using the seeded path so shots match the metadata.
```

## Shot list

| File | Scene | What you should see |
|------|-------|---------------------|
| `01-pantry.png` | Pantry tab | Desi staples, atta out, haldi low |
| `02-recipe-review.png` | Recipe capture **Review** | `turmeric` next to *haldi — andaza se* |
| `03-shopping-list.png` | Patel Brothers list | Some rows checked (In Cart), some still To Buy |
| `04-home.png` | Home dashboard | Running low + the active list together |
| `05-paywall.png` | RevenueCat paywall | Whatever the live offering UI renders |

Captions (from the metadata draft): “See what's low before you shop”, “Your
mother's exact words, kept”.

The recipe-review shot does **not** call `extract-recipe`. The review UI is
opened with the same canned `ExtractedRecipe` the seeder stores, so a missing
Edge Function cannot block screenshots.

The paywall is the real `PaywallView()`. If StoreKit/RevenueCat shows a
spinner or empty offering, that is still the honest capture — do not paste in
a Figma frame.

## XCUITest (optional)

`SamanUITests/AppStoreScreenshotUITests.swift` launches each scene, waits for
accessibility identifiers (`screenshot.pantry`, `screenshot.recipeReview`, …),
and attaches PNGs to the test report. Run via the script (`--uitest`) or:

```sh
xcodebuild test \
  -project Saman.xcodeproj \
  -scheme Saman \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:SamanUITests/AppStoreScreenshotUITests
```

## Linux / CI

This Cloud Agent / Ubuntu CI cannot boot `simctl`. The script is still
syntax-checked (`bash -n`) and `--dry-run` exits 0 without writing images.
Run the real capture on a Mac before uploading to App Store Connect.
