#!/usr/bin/env bash
# Cloud Agent install phase for the Saman Pantry backend.
#
# The iOS app itself needs macOS/Xcode and cannot build here. What IS runnable
# on Linux is the server side the app talks to: the Supabase Postgres schema
# (supabase/migrations) and the Deno Edge Functions (supabase/functions). This
# script installs the durable toolchain for that backend. It is idempotent and
# safe to re-run; per-boot services live in start.sh.
set -euo pipefail

SUPABASE_CLI_VERSION="2.116.0"

log() { echo "[install] $*"; }

# --- Docker engine (needed by the Supabase local stack) ---------------------
if ! command -v docker >/dev/null 2>&1; then
  log "installing Docker engine"
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
else
  log "Docker already installed ($(docker --version))"
fi

# fuse-overlayfs storage driver works inside the nested Cloud Agent VM where
# the default overlay2 driver is not usable.
if ! command -v fuse-overlayfs >/dev/null 2>&1; then
  log "installing fuse-overlayfs"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends fuse-overlayfs
else
  log "fuse-overlayfs already installed"
fi

log "writing /etc/docker/daemon.json (fuse-overlayfs storage driver)"
sudo mkdir -p /etc/docker
printf '{\n  "storage-driver": "fuse-overlayfs"\n}\n' | sudo tee /etc/docker/daemon.json >/dev/null

# --- Supabase CLI ------------------------------------------------------------
if ! command -v supabase >/dev/null 2>&1 || [ "$(supabase --version 2>/dev/null)" != "$SUPABASE_CLI_VERSION" ]; then
  log "installing Supabase CLI v${SUPABASE_CLI_VERSION}"
  curl -fsSL -o /tmp/supabase.deb \
    "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_${SUPABASE_CLI_VERSION}_linux_amd64.deb"
  sudo dpkg -i /tmp/supabase.deb
else
  log "Supabase CLI already at v${SUPABASE_CLI_VERSION}"
fi

# --- Deno (Edge Function type-checking / local tooling) ----------------------
if ! command -v deno >/dev/null 2>&1; then
  log "installing Deno"
  curl -fsSL https://deno.land/install.sh | sudo DENO_INSTALL=/usr/local sh
else
  log "Deno already installed ($(deno --version 2>/dev/null | head -1))"
fi

log "install phase complete"
log "docker:   $(docker --version 2>/dev/null || echo MISSING)"
log "supabase: $(supabase --version 2>/dev/null || echo MISSING)"
log "deno:     $(deno --version 2>/dev/null | head -1 || echo MISSING)"
