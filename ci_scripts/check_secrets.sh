#!/usr/bin/env bash
set -euo pipefail

# Fail fast on private provider keys that should never ship in source.
patterns=(
  'sk-ant-api[[:alnum:]_-]*'
  'sk-proj-[[:alnum:]_-]+'
  'sk-[[:alnum:]_-]{32,}'
)

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
file_list=$(mktemp)
trap 'rm -f "$file_list"' EXIT

# Only these reviewed exclusions may remove tracked files from the scan.
# Materialize the list so a Git failure cannot look like an empty scan.
git ls-files -z -- . \
  ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.jpeg' \
  ':(exclude)*.ttf' ':(exclude)*.pages' ':(exclude)*.xcuserstate' \
  ':(exclude)ci_scripts/check_secrets.sh' > "$file_list"

pattern_args=()
for pattern in "${patterns[@]}"; do
  pattern_args+=(-e "$pattern")
done

while IFS= read -r -d '' file; do
  # Explicit paths and disabled configuration prevent checkout ignore rules
  # from hiding credentials. Text mode also scans past embedded NUL bytes.
  if rg --no-config --no-ignore --text --with-filename -n "${pattern_args[@]}" -- "./$file"; then
    echo "Potential private API key detected. Move it to server-side secrets before committing." >&2
    exit 1
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      echo "Private API key scan failed while inspecting: $file" >&2
      exit "$status"
    fi
  fi
done < "$file_list"
