#!/usr/bin/env bash
# Re-renders the App Store "Header and Search Results" creative assets from
# marketing/app-store/creative/src into exact-spec PNGs (sRGB, 8-bit, no alpha).
#   Header:         3840x1646 (21:9)
#   Search Results: 3840x2560 (3:2)
# Needs: node + playwright, ImageMagick. Run scripts/fetch-fonts.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."
test -f fonts/fonts-local.css || { echo "run scripts/fetch-fonts.sh first"; exit 1; }
mkdir -p build
node scripts/render.cjs still app-store/creative/src/header.html build/raw-header.png 1920 823 3
node scripts/render.cjs still app-store/creative/src/search.html build/raw-search.png 1920 1280 3
flat="-background white -alpha remove -alpha off -colorspace sRGB -depth 8 -strip"
convert build/raw-header.png -resize 3840x1646! $flat app-store/creative/Header-3840x1646.png
convert build/raw-search.png -resize 3840x2560! $flat app-store/creative/SearchResults-3840x2560.png
identify -format "%f %wx%h alpha=%A\n" app-store/creative/*.png
