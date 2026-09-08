#!/usr/bin/env bash
# Capture App Store screenshots from the iOS Simulator.
#
# Mac-only. Boots a Simulator, launches Saman with a seeded desi kitchen
# (-UITesting), and writes real PNGs via `simctl io screenshot`.
# Does not generate marketing mockups.
#
# Usage:
#   ./scripts/capture-app-store-screenshots.sh
#   ./scripts/capture-app-store-screenshots.sh --dry-run
#   ./scripts/capture-app-store-screenshots.sh --appearance light
#   ./scripts/capture-app-store-screenshots.sh --uitest
#
# Optional demo-account UITest path (not used by simctl; simctl cannot type):
#   SAMAN_DEMO_EMAIL=review@samanpantry.com \
#   SAMAN_DEMO_PASSWORD='...' \
#   ./scripts/capture-app-store-screenshots.sh --uitest --demo-account

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.samanpantry.Saman"
SCHEME="Saman"
PROJECT="Saman.xcodeproj"
PREFERRED_DEVICE="iPhone 16 Pro"
OUT_DIR="${ROOT}/artifacts/app-store-screenshots"
DERIVED_DATA="${ROOT}/artifacts/derived-data"
SETTLE_SECONDS="${SETTLE_SECONDS:-4}"

DRY_RUN=0
SKIP_PAYWALL=0
RUN_UITEST=0
USE_DEMO_ACCOUNT=0
DEVICE_NAME=""
APPEARANCE="dark"

usage() {
  cat <<'EOF'
Capture real iOS Simulator screenshots for App Store Connect.

  ./scripts/capture-app-store-screenshots.sh [options]

Options:
  --dry-run           Print the plan. Works on Linux. Does not write PNGs.
  --device NAME       Simulator device name (default: iPhone 16 Pro, else newest iPhone Pro)
  --appearance dark|light
                      Simulator + app color scheme (default: dark). Dark is the
                      forest-green look on device. Light is cream doodh.
  --uitest            Also run SamanUITests/AppStoreScreenshotUITests
  --demo-account      With --uitest, sign in using SAMAN_DEMO_EMAIL / SAMAN_DEMO_PASSWORD
                      instead of -UITesting. simctl capture still uses -UITesting.
  --output DIR        Output directory (default: ./artifacts/app-store-screenshots)
  --help              Show this help

Environment:
  SAMAN_DEMO_EMAIL / SAMAN_DEMO_PASSWORD
      Pre-confirmed reviewer account. Required only for --uitest --demo-account.
      The default path does not need an account: -UITesting skips AuthView and
      seeds the shot-list kitchen. This is not guest mode.

  SETTLE_SECONDS      Pause after launch before capturing (default: 4)

Output (created on a successful Mac run):
  artifacts/app-store-screenshots/01-pantry.png
  artifacts/app-store-screenshots/02-recipe-review.png
  artifacts/app-store-screenshots/03-shopping-list.png
  artifacts/app-store-screenshots/04-home.png
  artifacts/app-store-screenshots/05-paywall.png   (unless --skip-paywall)
  artifacts/app-store-screenshots/MANIFEST.md

This path never invents marketing images. If it cannot boot a Simulator, it
exits without writing PNGs. See docs/launch/app-store-screenshots.md.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --skip-paywall) SKIP_PAYWALL=1; shift ;;
    --appearance)
      APPEARANCE="${2:?--appearance requires dark or light}"
      case "$APPEARANCE" in
        dark|light) ;;
        *)
          echo "--appearance must be dark or light, got: ${APPEARANCE}" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --uitest) RUN_UITEST=1; shift ;;
    --demo-account) USE_DEMO_ACCOUNT=1; shift ;;
    --device)
      DEVICE_NAME="${2:?--device requires a name}"
      shift 2
      ;;
    --output)
      OUT_DIR="${2:?--output requires a directory}"
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$DEVICE_NAME" ]]; then
  DEVICE_NAME="$PREFERRED_DEVICE"
fi

SHOTS=()
SHOTS+=("01-pantry.png|pantry|See what's low before you shop|Pantry with desi staples + low-stock dots (haldi low, atta out)")
SHOTS+=("02-recipe-review.png|recipeReview|Your mother's exact words, kept|Recipe capture review: turmeric next to “haldi — andaza se”")
SHOTS+=("03-shopping-list.png|shoppingList|Check off as you shop|Shopping list mid-checkout (Patel Brothers)")
SHOTS+=("04-home.png|home|Running low and the list, together|Home dashboard: running low + active list")
if [[ "$SKIP_PAYWALL" -eq 0 ]]; then
  SHOTS+=("05-paywall.png|paywall|Unlimited recipe capture + sync|Optional paywall (real RevenueCat UI, not a mock)")
fi

print_plan() {
  echo "Saman Pantry — App Store screenshot capture"
  echo "  project:     ${PROJECT} / scheme ${SCHEME}"
  echo "  bundle id:   ${BUNDLE_ID}"
  echo "  preferred:   ${DEVICE_NAME}"
  echo "  output:      ${OUT_DIR}"
  echo "  launch args: -UITesting -ScreenshotSeed -ScreenshotScene <scene> -ScreenshotAppearance ${APPEARANCE}"
  echo "  appearance:  ${APPEARANCE} (dark = green cards, matching a Dark Mode device)"
  echo "  auth:        skipped via -UITesting (not guest mode)"
  if [[ "$USE_DEMO_ACCOUNT" -eq 1 ]]; then
    echo "  uitest auth: SAMAN_DEMO_EMAIL demo account"
  fi
  echo "  shots:"
  local entry filename scene caption
  for entry in "${SHOTS[@]}"; do
    IFS='|' read -r filename scene caption _ <<< "$entry"
    echo "    - ${filename}  scene=${scene}  ${caption}"
  done
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_plan
    echo
    echo "Dry run on $(uname -s): capture requires macOS with Xcode + Simulator."
    echo "No PNGs written (this environment cannot run simctl)."
    exit 0
  fi
  echo "This screenshot capture path is Mac-only (xcodebuild + simctl)." >&2
  echo "Re-run on a Mac, or pass --dry-run to print the plan." >&2
  echo "See docs/launch/app-store-screenshots.md." >&2
  exit 2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_plan
  echo
  echo "Dry run: would boot Simulator, build ${SCHEME}, and write PNGs to ${OUT_DIR}."
  exit 0
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 2
  fi
}

need xcodebuild
need xcrun
need python3

pick_device() {
  local prefer="$1"
  # Pipe JSON into Python stdin. Do not combine with a heredoc — that would
  # steal stdin and make json.load() read the script instead of simctl output.
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
prefer = sys.argv[1]
data = json.load(sys.stdin)
candidates = []
for runtime, devices in data.get("devices", {}).items():
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name") or ""
        udid = device.get("udid")
        if "iPhone" not in name or not udid:
            continue
        candidates.append((name, udid, runtime))

def rank(name):
    m = re.search(r"iPhone (\d+) Pro$", name)
    if m:
        return (3, int(m.group(1)))
    m = re.search(r"iPhone (\d+) Pro Max$", name)
    if m:
        return (2, int(m.group(1)))
    m = re.search(r"iPhone (\d+)$", name)
    if m:
        return (1, int(m.group(1)))
    return (0, 0)

for name, udid, runtime in candidates:
    if name == prefer:
        print("%s\t%s\t%s" % (udid, name, runtime))
        raise SystemExit(0)

iphone_pro = [c for c in candidates if re.search(r"iPhone \d+ Pro$", c[0])]
pool = iphone_pro or [c for c in candidates if "Pro Max" in c[0]] or candidates
if not pool:
    raise SystemExit(1)
pool.sort(key=lambda c: rank(c[0]), reverse=True)
name, udid, runtime = pool[0]
print("%s\t%s\t%s" % (udid, name, runtime))
' "$prefer"
}

DEVICE_LINE="$(pick_device "$DEVICE_NAME")" || {
  echo "No available iPhone Simulator found. Open Xcode and install an iPhone runtime." >&2
  exit 2
}

UDID="$(printf '%s' "$DEVICE_LINE" | cut -f1)"
RESOLVED_NAME="$(printf '%s' "$DEVICE_LINE" | cut -f2)"
RUNTIME="$(printf '%s' "$DEVICE_LINE" | cut -f3)"

echo "Using Simulator: ${RESOLVED_NAME} (${UDID})"
echo "Runtime: ${RUNTIME}"

mkdir -p "$OUT_DIR" "$DERIVED_DATA"

echo "Booting Simulator…"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance "$APPEARANCE" >/dev/null 2>&1 || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true

echo "Building ${SCHEME} for Simulator…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$(find "$DERIVED_DATA" -path '*/Build/Products/Debug-iphonesimulator/Saman.app' -print | head -n 1 || true)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Built app not found under ${DERIVED_DATA}" >&2
  exit 1
fi

echo "Installing ${APP_PATH}"
xcrun simctl install "$UDID" "$APP_PATH"

capture_scene() {
  local filename="$1"
  local scene="$2"
  echo "Capturing ${filename} (scene=${scene})…"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    -UITesting \
    -ScreenshotSeed \
    -ScreenshotScene "$scene" \
    -ScreenshotAppearance "$APPEARANCE" >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$UDID" screenshot "${OUT_DIR}/${filename}"
}

for entry in "${SHOTS[@]}"; do
  IFS='|' read -r filename scene _caption _desc <<< "$entry"
  capture_scene "$filename" "$scene"
done

write_manifest() {
  local generated
  generated="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  cat > "${OUT_DIR}/MANIFEST.md" <<EOF
# App Store screenshots

Generated: ${generated}
Device: ${RESOLVED_NAME}
UDID: ${UDID}
Runtime: ${RUNTIME}
Launch: \`-UITesting -ScreenshotSeed -ScreenshotScene <scene> -ScreenshotAppearance ${APPEARANCE}\`
Appearance: ${APPEARANCE} (Dark Mode uses the forest-green surfaces from the asset catalog)
Auth: skipped via \`-UITesting\` (not guest mode). Demo kitchen is local SwiftData seed.

These are Simulator captures from this machine. Do not replace them with
invented marketing images.

| File | Scene | Caption (from docs/launch/app-store-metadata.md) | What should be on screen |
|------|-------|---------------------------------------------------|--------------------------|
EOF
  local entry filename scene caption desc
  for entry in "${SHOTS[@]}"; do
    IFS='|' read -r filename scene caption desc <<< "$entry"
    printf '| `%s` | `%s` | %s | %s |\n' "$filename" "$scene" "$caption" "$desc" >> "${OUT_DIR}/MANIFEST.md"
  done
  cat >> "${OUT_DIR}/MANIFEST.md" <<EOF

## How to recapture

\`\`\`sh
./scripts/capture-app-store-screenshots.sh
\`\`\`

See \`docs/launch/app-store-screenshots.md\`.
EOF
}

write_manifest

if [[ "$RUN_UITEST" -eq 1 ]]; then
  echo "Running AppStoreScreenshotUITests…"
  UITEST_ARGS=(
    xcodebuild test
    -project "$PROJECT"
    -scheme "$SCHEME"
    -destination "platform=iOS Simulator,id=${UDID}"
    -derivedDataPath "$DERIVED_DATA"
    -only-testing:SamanUITests/AppStoreScreenshotUITests
  )
  if [[ "$USE_DEMO_ACCOUNT" -eq 1 ]]; then
    if [[ -z "${SAMAN_DEMO_EMAIL:-}" || -z "${SAMAN_DEMO_PASSWORD:-}" ]]; then
      echo "--demo-account requires SAMAN_DEMO_EMAIL and SAMAN_DEMO_PASSWORD." >&2
      exit 1
    fi
    UITEST_ARGS+=(
      TEST_RUNNER_CAPTURE_USE_DEMO_ACCOUNT=1
      "TEST_RUNNER_SAMAN_DEMO_EMAIL=${SAMAN_DEMO_EMAIL}"
      "TEST_RUNNER_SAMAN_DEMO_PASSWORD=${SAMAN_DEMO_PASSWORD}"
    )
  fi
  "${UITEST_ARGS[@]}"
fi

echo
echo "Wrote screenshots to ${OUT_DIR}"
ls -1 "$OUT_DIR"
echo "Done."
