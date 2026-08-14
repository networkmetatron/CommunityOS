#!/usr/bin/env bash

# shellcheck disable=SC2034

set -euo pipefail

COMMUNITYOS_ROOT="${COMMUNITYOS_ROOT:-/opt/communityos}"

# Load persisted offline mode if this installation was created offline.
# This keeps later CLI operations (app install/update/restart) air-gapped.
# shellcheck source=/dev/null
if [[ -f "${COMMUNITYOS_ROOT}/runtime/offline.env" ]]; then
  source "${COMMUNITYOS_ROOT}/runtime/offline.env"
fi

log_info() { echo "[INFO] $*"; }
log_ok() { echo "[ OK ] $*"; }
log_fail() { echo "[FAIL] $*"; }
log_warn() { echo "[WARN] $*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run with sudo:"
    echo "  sudo communityos $*"
    exit 1
  fi
}

# shellcheck source=/dev/null
[[ -f "${COMMUNITYOS_ROOT}/lib/apps.sh" ]] && source "${COMMUNITYOS_ROOT}/lib/apps.sh"

compose() {
  if [[ ! -r "${COMMUNITYOS_ROOT}/.env" ]]; then
    echo "Cannot read ${COMMUNITYOS_ROOT}/.env (permission denied)."
    echo "Run with sudo, or:  sudo usermod -aG docker $USER  &&  sudo chgrp docker ${COMMUNITYOS_ROOT}/.env && sudo chmod 640 ${COMMUNITYOS_ROOT}/.env"
    echo "Then log out and back in."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is not available to this user."
    echo "Run:  sudo usermod -aG docker $USER"
    echo "Then log out and back in (or use sudo communityos ...)."
    exit 1
  fi

  if declare -F service_sync_compose_profiles >/dev/null 2>&1; then
    service_sync_compose_profiles
  fi
  if declare -F compose_with_apps >/dev/null 2>&1; then
    compose_with_apps "$@"
  else
    docker compose -f "${COMMUNITYOS_ROOT}/compose.yaml" --env-file "${COMMUNITYOS_ROOT}/.env" "$@"
  fi
}

ensure_installed() {
  if [[ ! -f "${COMMUNITYOS_ROOT}/.env" ]]; then
    echo "CommunityOS is not installed."
    echo "Run:  sudo communityos install"
    exit 1
  fi
}
