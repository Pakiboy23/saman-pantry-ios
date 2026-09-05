#!/usr/bin/env bash
# Cloud Agent start phase: bring up the Docker daemon and the Supabase local
# stack (Postgres + Auth + REST + Edge Functions) that back the iOS app.
# Runs on every boot; must be idempotent and must return once the stack is up.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SAMAN_PHASE="start"
# shellcheck source=/dev/null
source "$REPO_ROOT/.cursor/lib.sh"

saman_ensure_docker || { saman_log "could not start docker or apply required nested-VM networking; see /var/log/dockerd.log"; exit 1; }

# `supabase start` is a no-op when the stack is already up, so this is safe to
# re-run. It applies supabase/migrations and serves supabase/functions.
cd "$REPO_ROOT"
saman_log "starting Supabase stack (applies migrations, serves edge functions)"
supabase start 2>&1 | tail -3 || {
  saman_log "supabase start reported an error; printing status"
  supabase status || true
  exit 1
}
saman_log "Supabase stack is up on http://127.0.0.1:54321"
