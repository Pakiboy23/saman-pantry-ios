#!/usr/bin/env bash
set -euo pipefail

# Fail fast on private provider keys that should never ship in source.
patterns=(
  'sk-ant-api[[:alnum:]_-]*'
  'sk-proj-[[:alnum:]_-]+'
  'sk-[[:alnum:]_-]{32,}'
)

for pattern in "${patterns[@]}"; do
  if rg --hidden --glob '!*.png' --glob '!*.jpg' --glob '!*.jpeg' --glob '!*.ttf' --glob '!*.pages' --glob '!*.xcuserstate' --glob '!APP_STORE_READINESS_REPORT.md' --glob '!ci_scripts/check_secrets.sh' -n "$pattern" .; then
    echo "Potential private API key detected. Move it to server-side secrets before committing." >&2
    exit 1
  fi
done
