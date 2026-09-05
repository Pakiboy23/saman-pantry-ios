#!/usr/bin/env bash
# Shared helpers for the Saman Pantry Cloud Agent environment scripts.
# Sourced by install.sh and start.sh.

saman_log() { echo "[${SAMAN_PHASE:-env}] $*"; }

# Bring the Docker daemon up (if it is not already) and apply the networking
# fixes the nested Cloud Agent VM needs. Idempotent.
saman_ensure_docker() {
  if ! sudo docker info >/dev/null 2>&1; then
    saman_log "starting dockerd"
    sudo mkdir -p /var/log
    sudo setsid bash -c 'dockerd >/var/log/dockerd.log 2>&1' >/dev/null 2>&1 &
    local i
    for i in $(seq 1 60); do
      sudo docker info >/dev/null 2>&1 && break
      sleep 1
    done
    sudo docker info >/dev/null 2>&1 || { saman_log "dockerd failed to start; see /var/log/dockerd.log"; return 1; }
  else
    saman_log "dockerd already running"
  fi

  # Let the non-root agent user use the socket without sudo.
  sudo chmod 666 /var/run/docker.sock || true

  # Same-bridge container traffic must switch at L2 instead of traversing a
  # conflicted (nftables + iptables-legacy) netfilter FORWARD path.
  sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
  sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true
  sudo sysctl -w net.bridge.bridge-nf-call-arptables=0 >/dev/null 2>&1 || true
  # The pod's iptables-legacy FORWARD chain defaults to DROP, which kills
  # container egress (Docker programs its ACCEPT rules only in nftables).
  sudo iptables-legacy -P FORWARD ACCEPT 2>/dev/null || true
}
