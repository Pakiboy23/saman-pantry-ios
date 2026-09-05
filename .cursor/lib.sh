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

  # Grant the agent user socket access without making it world-writable.
  # Group membership is set in install.sh; the current session may not have
  # the new group yet, so apply a per-user ACL for immediate use.
  local agent_user
  agent_user="$(id -un)"
  if ! docker info >/dev/null 2>&1; then
    if ! command -v setfacl >/dev/null 2>&1; then
      saman_log "setfacl is required to grant ${agent_user} access to /var/run/docker.sock (install the acl package)"
      return 1
    fi
    sudo setfacl -m "u:${agent_user}:rw" /var/run/docker.sock || {
      saman_log "could not grant ${agent_user} write access to /var/run/docker.sock"
      return 1
    }
    if ! docker info >/dev/null 2>&1; then
      saman_log "docker socket still not usable by ${agent_user} after ACL"
      return 1
    fi
  fi

  # Required nested-VM networking. Fail loudly — swallowing errors here lets
  # supabase start "succeed" while Edge Functions cannot reach Anthropic.
  sudo modprobe br_netfilter >/dev/null 2>&1 || true
  if ! sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null; then
    saman_log "failed to disable net.bridge.bridge-nf-call-iptables (required for container L2 switching)"
    return 1
  fi
  if ! sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null; then
    saman_log "failed to disable net.bridge.bridge-nf-call-ip6tables (required for container L2 switching)"
    return 1
  fi
  if ! sudo sysctl -w net.bridge.bridge-nf-call-arptables=0 >/dev/null; then
    saman_log "failed to disable net.bridge.bridge-nf-call-arptables (required for container L2 switching)"
    return 1
  fi
  if ! command -v iptables-legacy >/dev/null 2>&1; then
    saman_log "iptables-legacy is required for Cloud Agent container egress; install it in install.sh"
    return 1
  fi
  if ! sudo iptables-legacy -P FORWARD ACCEPT; then
    saman_log "failed to set iptables-legacy FORWARD policy to ACCEPT"
    return 1
  fi
  local forward_policy
  forward_policy="$(sudo iptables-legacy -S FORWARD | awk '/^-P FORWARD / { print $3; exit }')"
  if [ "${forward_policy}" != "ACCEPT" ]; then
    saman_log "iptables-legacy FORWARD policy is ${forward_policy:-unknown}, expected ACCEPT"
    return 1
  fi
}
