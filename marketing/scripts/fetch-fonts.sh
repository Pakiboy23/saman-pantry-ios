#!/usr/bin/env bash
# Downloads the brand fonts (Cormorant Garamond, IBM Plex Mono, Noto Nastaliq Urdu)
# from Google Fonts into marketing/fonts/ and writes fonts-local.css pointing at the
# local files. Headless Chromium renders with these, so no network is needed at
# render time. marketing/fonts/ is gitignored.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p fonts
cd fonts
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
CSS='https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,600;0,700;1,500;1,600&family=IBM+Plex+Mono:wght@400;500&family=Noto+Nastaliq+Urdu&display=swap'
curl -fsS -H "User-Agent: $UA" "$CSS" -o fonts.css
cp fonts.css fonts-local.css
i=0
for u in $(grep -oE 'https://[^) ]*\.woff2' fonts.css | sort -u); do
  i=$((i+1)); fn="f${i}.woff2"
  curl -fsS -H "User-Agent: $UA" "$u" -o "$fn"
  sed -i.bak "s|$u|$fn|g" fonts-local.css
done
rm -f fonts-local.css.bak
echo "fonts: $i files -> marketing/fonts/fonts-local.css"
