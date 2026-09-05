#!/usr/bin/env bash
# Cloud Agent install phase for the Saman Pantry backend.
#
# The iOS app itself needs macOS/Xcode and cannot build here. What IS runnable
# on Linux is the server side the app talks to: the Supabase Postgres schema
# (supabase/migrations) and the Deno Edge Functions (supabase/functions). This
# script installs the durable toolchain for that backend and warms the Supabase
# Docker images so fresh agents boot fast. It is idempotent and safe to re-run;
# per-boot services live in start.sh.
set -euo pipefail

SUPABASE_CLI_VERSION="2.116.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SAMAN_PHASE="install"
# shellcheck source=/dev/null
source "$REPO_ROOT/.cursor/lib.sh"

# --- Docker engine (needed by the Supabase local stack) ---------------------
if ! command -v docker >/dev/null 2>&1; then
  saman_log "installing Docker engine"
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
else
  saman_log "Docker already installed ($(docker --version))"
fi

# fuse-overlayfs storage driver works inside the nested Cloud Agent VM where
# the default overlay2 driver is not usable.
if ! command -v fuse-overlayfs >/dev/null 2>&1; then
  saman_log "installing fuse-overlayfs"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends fuse-overlayfs
else
  saman_log "fuse-overlayfs already installed"
fi

saman_log "writing /etc/docker/daemon.json (fuse-overlayfs storage driver)"
sudo mkdir -p /etc/docker
printf '{\n  "storage-driver": "fuse-overlayfs"\n}\n' | sudo tee /etc/docker/daemon.json >/dev/null

# --- Supabase CLI ------------------------------------------------------------
if ! command -v supabase >/dev/null 2>&1 || [ "$(supabase --version 2>/dev/null)" != "$SUPABASE_CLI_VERSION" ]; then
  saman_log "installing Supabase CLI v${SUPABASE_CLI_VERSION}"
  curl -fsSL -o /tmp/supabase.deb \
    "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_${SUPABASE_CLI_VERSION}_linux_amd64.deb"
  sudo dpkg -i /tmp/supabase.deb
else
  saman_log "Supabase CLI already at v${SUPABASE_CLI_VERSION}"
fi

# --- Deno (Edge Function type-checking / local tooling) ----------------------
if ! command -v deno >/dev/null 2>&1; then
  saman_log "installing Deno"
  curl -fsSL https://deno.land/install.sh | sudo DENO_INSTALL=/usr/local sh
else
  saman_log "Deno already installed ($(deno --version 2>/dev/null | head -1))"
fi

# --- Warm the Supabase Docker images ----------------------------------------
# Pulling ~2.5GB of images is durable state, so do it here where it can be
# baked into the environment build snapshot instead of paid on every boot.
# Best-effort: if nested Docker is unavailable at build time, start.sh still
# pulls the images on first boot, so a failure here must not fail install.
saman_log "warming Supabase Docker images (best-effort)"
if saman_ensure_docker; then
  cd "$REPO_ROOT"
  if supabase start >/dev/null 2>&1; then
    saman_log "images warmed; stopping stack (images stay cached on disk)"
    supabase stop --no-backup >/dev/null 2>&1 || true
  else
    saman_log "supabase start during warm-up did not complete; start.sh will pull images on first boot"
    supabase stop --no-backup >/dev/null 2>&1 || true
  fi
else
  saman_log "docker unavailable during install; start.sh will pull images on first boot"
fi

saman_log "install phase complete"
saman_log "docker:   $(docker --version 2>/dev/null || echo MISSING)"
saman_log "supabase: $(supabase --version 2>/dev/null || echo MISSING)"
saman_log "deno:     $(deno --version 2>/dev/null | head -1 || echo MISSING)"
