#!/usr/bin/env bash
# Cloud Agent start phase: bring up the Docker daemon and the Supabase local
# stack (Postgres + Auth + REST + Edge Functions) that back the iOS app.
# Runs on every boot; must be idempotent and must return once the stack is up.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { echo "[start] $*"; }

# --- Docker daemon -----------------------------------------------------------
if ! sudo docker info >/dev/null 2>&1; then
  log "starting dockerd"
  sudo mkdir -p /var/log
  sudo setsid bash -c 'dockerd >/var/log/dockerd.log 2>&1' >/dev/null 2>&1 &
  for i in $(seq 1 60); do
    sudo docker info >/dev/null 2>&1 && break
    sleep 1
  done
  sudo docker info >/dev/null 2>&1 || { log "dockerd failed to start; see /var/log/dockerd.log"; exit 1; }
else
  log "dockerd already running"
fi

# Let the non-root agent user use the socket without sudo.
sudo chmod 666 /var/run/docker.sock || true

# --- Nested-VM networking fixes ---------------------------------------------
# 1. Same-bridge container traffic must switch at L2 instead of being sent
#    through a conflicted (nftables + legacy) netfilter FORWARD path.
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true
sudo sysctl -w net.bridge.bridge-nf-call-arptables=0 >/dev/null 2>&1 || true
# 2. The pod's iptables-legacy FORWARD chain defaults to DROP, which kills
#    container egress (Docker programs its ACCEPT rules only in nftables).
sudo iptables-legacy -P FORWARD ACCEPT 2>/dev/null || true

# --- Supabase local stack ----------------------------------------------------
# `supabase start` is a no-op when the stack is already up, so this is safe to
# re-run. It applies supabase/migrations and serves supabase/functions.
cd "$REPO_ROOT"
log "starting Supabase stack (applies migrations, serves edge functions)"
supabase start 2>&1 | tail -3 || {
  log "supabase start reported an error; printing status"
  supabase status || true
  exit 1
}
log "Supabase stack is up on http://127.0.0.1:54321"
